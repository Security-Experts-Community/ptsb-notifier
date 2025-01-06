# базовый образ питона для работы кода
FROM python:3.11-slim

# Устанавливаем необходимые локали
RUN apt-get update && apt-get install -y locales

# Добавляем русскую локаль и генерируем её
RUN echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# рабочая директория внутри докер имаджа
WORKDIR /opt/ptsb-notifier

# перенос содержимого проекта в докер-образ
COPY ptsb-notifier ./

# устанавливаем зависимости для проекта
RUN pip install --no-cache-dir -r requirements.txt

# пробрасываем порт
EXPOSE 514

# запуск контейнера
CMD [ "python", "ptsb-notifier.py"]