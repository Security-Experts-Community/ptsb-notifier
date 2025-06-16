# либы
import asyncio as asyncio_lib
import json as json_lib
import locale as locale_lib
import os as os_lib
import re as re_lib
import signal as signal_lib
import socket as socket_lib

# классы
from aiogram import Bot as Bot_class
from aiogram.types import (
    InlineKeyboardMarkup as KeyboardMarkup_class,
    InlineKeyboardButton as KeyboardButton_class,
)
from concurrent.futures import ThreadPoolExecutor as ThreadPoolExecutor_class
from datetime import (
    datetime as datetime_class,
    timezone as timezone_class,
    timedelta as timedelta_class,
)
from typing import Union as Union_class


# параметры создаваемого сервера
HOST = "0.0.0.0"                        # интерфейс, на котором слушаем весь входящий трафик
PORT = 514                              # локальный порт, на котором TCP сервер слушает входящий трафик
SESSION_SIZE = 10240                    # max объем трафика, который мы согласны получать в рамках одной сессии
SERVER_SOCKET = None                    # сущность, которая слушает входящий трафик addr:port                
IS_SEVER_SHUTDOWN_INITIATED = False     # флаг для того, чтобы вылкючение сервера вызывалось не больше одного раза

# настройки многопоточности
MAX_THREADS = 8
THREADS_EXECUTOR = ThreadPoolExecutor_class(max_workers=MAX_THREADS)

# параметры поиска событий и сохранения их в куда-то
NEEDED_EVENT_DESCRIPTION = "- scan_machine.final_result -"      # строка, по которой определяем, что это подходящее нам событие 
THREAT_FILTER_MODE = str(os_lib.getenv('THREAT_FILTER_MODE'))   # Фильтр, который указывает, какие из всех событий отправлять
THREAT_LEVEL_MAP = {                                            # Карта допустимых уровней угроз для каждого режима
    "ALL": ["UNKNOWN", "UNWANTED", "DANGEROUS"],
    "UNWANTED": ["UNWANTED", "DANGEROUS"],
    "DANGEROUS": ["DANGEROUS"],
}
ALLOWED_THREAT_LEVELS = THREAT_LEVEL_MAP.get(THREAT_FILTER_MODE, [])    # Определяем допустимые уровни
events_to_process_queue = asyncio_lib.Queue()       # очередь, в которую будем складывать все подходящие события

# импорт словарей-структур для красивого парсинга значений события в человеко-читаемый русский вид
PYTHON_FILE_PATH = os_lib.path.abspath(__file__)
DATA_SETS_DIR = os_lib.path.join(
    os_lib.path.dirname(PYTHON_FILE_PATH),
    "json_data_sets"
)
JSON_DATA_SETS = {}
for filename in os_lib.listdir(DATA_SETS_DIR):
    current_file_path = os_lib.path.join(DATA_SETS_DIR, filename)
    key_name = os_lib.path.splitext(filename)[0]
    with open(current_file_path, "r", encoding="utf-8") as json_f:
        JSON_DATA_SETS[key_name] = json_lib.load(json_f)

# параметры пт песка
PTSB_MAIN_WEB = str(os_lib.getenv('PTSB_MAIN_WEB'))  # адрес песочницы, который будет подставляться в кнопку для перехода к странице задания

# настройки TG бота
TG_BOT_TOKEN = str(os_lib.getenv('TG_BOT_TOKEN'))   # токен бота, который будет использоваться для доступа к telegram api
TG_CHAT_ID = int(os_lib.getenv('TG_CHAT_ID'))       # id чата, куда бот будет отправлять уведомления
MESSAGE_LIMIT = 20                                  # max количество сообщений в минуту, разрешенное разрабами TG для ботов
TG_BOT = Bot_class(token=TG_BOT_TOKEN)              # сущность Бот

# параметры отправки уведомлений
locale_lib.setlocale(locale_lib.LC_TIME, 'ru_RU.utf-8')         # для того, чтобы в уведомлениях отображался месяц красиво
UTC_CUSTOM_OFFSET = int(os_lib.getenv('UTC_CUSTOM_OFFSET'))     # смещение в часах относительно UTC времени для красивого отображения времени
QUEUE_CHECK_DELAY = 5       # количество секунд, как часто будет проверяться пуста ли очередь или нет


#----------------------------------------------------------------------------------------------------------------------#
# Обработка одного события
def process_event(event_data: str) -> Union_class[dict, None]:
    """
    Получает каждое отдельно взятое syslog событие в формате строки.\n
    Проверяет описание события на наличие `NEEDED_EVENT_DESCRIPTION`, если подходит, то проверяет, что уровень угрозы удовлетворяет `ALLOWED_THREAT_LEVELS`.

    Параметры:
        - `event_data` (str): Отдельно взятое syslog событие в формате строки.

    Возвращает:
        `dict`: Распарсенные JSON-данные в виде словаря.\n
        `None`, если:
        - Строка не содержит описания нужного события.
        - JSON отсутствует или не может быть декодирован.
        - Значение `verdict` равно `CLEAN`.
    """

    # проверяем, есть ли то, что нужно
    if NEEDED_EVENT_DESCRIPTION not in event_data:
        return None

    try:
        json_match = re_lib.search(r"\{.*\}", event_data)
        if json_match:
            json_data_str = json_match.group(0)
            json_data_obj = json_lib.loads(json_data_str)
            event_verdict = json_data_obj['result']['verdict']['threat_level']
            if event_verdict not in ALLOWED_THREAT_LEVELS:
                return None
            return json_data_obj
        else:
            print(f"В событии\n{event_data}\nОтсутствуют JSON-данные.")
            return None
    except json_lib.JSONDecodeError as e:
        print(f"Ошибка декодирования JSON-объекта:\n{e}")
        return None


# Обработка подключения клиента
async def handle_client_connection(
    client_socket: socket_lib.socket,
    event_loop: asyncio_lib.AbstractEventLoop,
) -> None:
    """
    Обрабатывает подключения от клиента, получая данные в каждой tcp-сессии.
    Подходящие после всех обработок данные передаются в `events_to_process_queue` для последующей отправки в tg.
    
    Параметры:
        - `client_socket` (socket.socket): Сокет подключения удаленного клиента (ip:port)
        - `event_loop` (asyncio.AbstractEventLoop): Текущий цикл событий, используемый для асинхронных функций

    Возвращает:
        None
    """

    buffer = ""  # буфер для обработки каждого отдельного client_socket
    try:
        while True:
            received_data = await event_loop.sock_recv(
                client_socket, SESSION_SIZE
            )
            if not received_data:
                break

            buffer += received_data.decode("utf-8")

            while "\n" in buffer:
                current_line, buffer = buffer.split("\n", 1)
                result = await event_loop.run_in_executor(
                    THREADS_EXECUTOR,
                    process_event,
                    current_line.strip(),
                )
                if result is not None:
                    await events_to_process_queue.put(result)


    # ошибочки
    except asyncio_lib.CancelledError:
        print(f"Task cancelled from outside. Closing current connection with {client_socket}.")
    except Exception as e:
        print(f"\nError while handling client connection:\n{e}\n")
    finally:
        client_socket.close()
        if buffer.strip():
            result = await event_loop.run_in_executor(
                THREADS_EXECUTOR,
                process_event,
                buffer.strip(),
            )
            if result is not None:
                await events_to_process_queue.put(result)


# Запуск сервера
async def start_server(local_host_addr: str, local_port: int) -> None:
    """
    Запускает TCP-сервер, прослушивающий подключения клиентов на указанные addr:port.
    Создает async задачу обработки каждого входящего подключения.

    Параметры:
        - `local_host_addr` (str): Локальный адрес, на котором сервер будет слушать входищий трафик. "0.0.0.0" - чтобы слушать на всех интерфейсах.
        - `local_port` (int): Номер порта, на котором сервер будет слушать входящий трафик. 
    
    Возвращает:
        None
    """

    global SERVER_SOCKET
    SERVER_SOCKET = socket_lib.socket(socket_lib.AF_INET, socket_lib.SOCK_STREAM)
    SERVER_SOCKET.setsockopt(socket_lib.SOL_SOCKET, socket_lib.SO_REUSEADDR, 1)
    SERVER_SOCKET.bind((local_host_addr, local_port))
    SERVER_SOCKET.listen()
    SERVER_SOCKET.setblocking(False)
    current_loop = asyncio_lib.get_running_loop()
    print(f"Server listening on {local_host_addr}:{local_port}...")

    try:
        while True:
            client_socket, _ = await current_loop.sock_accept(SERVER_SOCKET)
            # TODO: logging Connection established with {addr} ?
            current_loop.create_task(
                handle_client_connection(client_socket, current_loop)
            )
    except asyncio_lib.CancelledError:
        print("Server task cancelled.")
    finally:
        SERVER_SOCKET.close()
        print("Server socket closed.")


# ф-ия конвертации UNIX времени в человеко-читаемое
async def get_datetime_with_offset(timestamp: float, offset_hours: int = 0) -> str:
    """
    Конвертирует timestamp в дату и время с указанным смещением относительно UTC. По умолчанию `offset_hours` = 0
    
    Параметры:
    - `timestamp` (float): UNIX timestamp временная метка, для которой нужно создать смещение.
    - `offset_hours` (int): Количество часов, на которое необходимо сместить возвращаемое значение.

    Возвращает:
        `str`: Человеко-читаемое представление времени, смещенное относительно UTC на указанное `offset_time` количество часов.
    """

    # Устанавливаем смещение
    custom_offset = timezone_class(timedelta_class(hours=offset_hours))
    return datetime_class.fromtimestamp(timestamp, tz=custom_offset).strftime('%H:%M // %d %B')


# отправлялка событий в тг-беседу
async def send_event_to_tg() -> None:
    """
    Асинхронно разгребает очередь событий `events_to_process_queue`.
    Отправляет каждое событие как отдельное сообщение в TG-беседу через сущность `TG_BOT`.
    """

    while True:
        # TODO: logging events_to_process_queue.qsize()? 
        # проверка на то, что очередь не пустая. если очередь пустая, то спим N секунд.
        if events_to_process_queue.qsize() == 0:
            await asyncio_lib.sleep(QUEUE_CHECK_DELAY)
            continue
        
        try:
            # само по себе событие
            current_event = await events_to_process_queue.get()
            
            # получаем scan_id текущего события
            scan_id = current_event['scan_id']
            # получаем уровень угрозы текущего события и переводим в красивый вид
            threat_level = current_event['result']['verdict']['threat_level']
            threat_level = JSON_DATA_SETS["threat_level"].get(threat_level)
            # получаем статус выполненного сканирования
            state = current_event['result']['state']
            state = JSON_DATA_SETS["result_state"].get(state)
            # получаем тип источника, откуда пришло задание
            entry_point = current_event['entry_point_type']
            entry_point = JSON_DATA_SETS["entry_point_type"].get(entry_point)
            # получаем классификацию обнаруженного ВПО
            classification = current_event['result']['verdict']['threat']['classification']
            classification = JSON_DATA_SETS["threat_classification"].get(classification)
            # получаем семейство, к которому относится ВПО
            family = current_event['result']['verdict']['threat']['family'] or "Семейство ВПО не определено"
            # получаем целевую платформу, на которую нацелено ВПО
            if current_event['result']['verdict']['threat']['platform'] == "NO_PLATFORM":
                platform = "Целевая ОС не определена"
            else:
                platform = current_event['result']['verdict']['threat']['platform']
            # получаем дату получения результатов в UTC и кастомном часовом поясе
            created_utc = await get_datetime_with_offset(current_event['created'])
            created_custom = await get_datetime_with_offset(current_event['created'], UTC_CUSTOM_OFFSET)
            
            # формируем кнопку со ссылкой на страницу задания в PTSB
            event_url_button = KeyboardButton_class(
                text="Перейти к заданию",
                url=f"https://{PTSB_MAIN_WEB}/tasks/{scan_id}"
            )
            message_keyboard = KeyboardMarkup_class(
                inline_keyboard=[[event_url_button]]
            )

            #формируем все сообщение
            message_to_chat = (
                #"<b>Новое задание требует внимания!</b>\n\n"
                f"<b>{threat_level}</b>\n\n"
                f"<b>Статус проверки:</b> {state}\n"
                f"<b>Источник</b>: {entry_point}\n\n"
                f"<b>Классификация ВПО:</b> {classification}\n"
                f"<b>Семейство ВПО:</b> {family}\n"
                f"<b>Целевая ОС ВПО:</b> {platform}\n\n"
                "<b>Вердикт получен в:</b>\n"
                f"{created_utc} // по UTC\n"
                f"{created_custom} // по местному"
            )

            await TG_BOT.send_message(
                chat_id=TG_CHAT_ID,
                text=message_to_chat,
                reply_markup=message_keyboard,
                parse_mode="HTML"
            )
            
        except Exception as e:
            print(f"Ошибка отправки сообщения в TG: {e}")
        finally:
            events_to_process_queue.task_done()
            await asyncio_lib.sleep(60 / MESSAGE_LIMIT)     # нужно, чтобы бот не получил бан по спаму по количесту отправляемых сообщений в минуту


# Завершение сервера
async def shutdown_server() -> None:
    """
    Завершает работу TCP-сервера на основании полученных сигналов.
    Останавливает все задачи, закрывает сокет и завершает пул потоков.
    """

    # TODO: всё бы в logging
    # проверка того, что ф-ия отключения уже выполнялась, чтобы избежать двойственного выполнения
    global IS_SEVER_SHUTDOWN_INITIATED
    if IS_SEVER_SHUTDOWN_INITIATED:
        return
    IS_SEVER_SHUTDOWN_INITIATED = True
    print("\nReceived shutdown signal. Closing server gracefully...")

    # списковое включение. создает список всех запущенных задач *all_tasks* кроме текущей *current_task*
    # все задачи из созданного списка отменяются 
    tasks = [t for t in asyncio_lib.all_tasks() if t is not asyncio_lib.current_task()]
    print(f"Cancelling {len(tasks)} tasks...")

    # TODO: wtf? утром подумать
    for task in tasks:
        task.cancel()
    try:
        await asyncio_lib.gather(*tasks, return_exceptions=True)
    except Exception as e:
        print(f"\nUnexpected exception occured:\n{e}\n")
    
    # завершение управлялки многопоточностью
    THREADS_EXECUTOR.shutdown(wait=True)
    print("Server shutdown completed.")


# Настройка обработки сигналов
def setup_signals(current_event_loop: asyncio_lib.AbstractEventLoop) -> None:
    """
    Настраивает обработку сигналов (`SIGINT`, `SIGTERM`) для корректного завершения работы сервера.

    Параметры:
        - `current_event_loop` (asyncio.AbstractEventLoop): Цикл событий, для которого настраиваются обработчики сигналов.

    Возвращаемое значение:
        None
    """

    for sig in (signal_lib.SIGINT, signal_lib.SIGTERM):
        current_event_loop.add_signal_handler(
            sig,
            lambda: asyncio_lib.create_task(shutdown_server()),
        )


# MAIN
async def main() -> None:
    # настраиваем TCP-сервер
    server_listener_task = asyncio_lib.create_task(start_server(HOST, PORT))

    # обработчик очереди отправки сообщений
    tg_event_sender_task = asyncio_lib.create_task(send_event_to_tg())

    try:
        await asyncio_lib.gather(server_listener_task, tg_event_sender_task)
    except asyncio_lib.CancelledError:
        print("\nЭкстренное завевершение программы. Закрываемся.\n")
    finally:
        server_listener_task.cancel()
        tg_event_sender_task.cancel()

        await asyncio_lib.gather(
            server_listener_task,
            tg_event_sender_task,
            return_exceptions=True,
        )
        print("\nGood Bye\n")


if __name__ == "__main__":
    # запуск цикла событий для асинхронности
    main_loop = asyncio_lib.new_event_loop()
    asyncio_lib.set_event_loop(main_loop)

    # установка сигналов экстренного завершения программы 
    setup_signals(main_loop)

    try:
        main_loop.run_until_complete(main())
    except (KeyboardInterrupt, SystemExit):
        print("Server stopped by user.")
    finally:
        main_loop.run_until_complete(shutdown_server())
        main_loop.close()