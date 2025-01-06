# базовый образ Python
FROM python:3.11-slim

# устанавливаем необходимые локали и зависимости, добавляем русскую локаль
RUN apt-get update && apt-get install -y --no-install-recommends locales && \
    echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# устанавливаем рабочую директорию внутри контейнера
WORKDIR /opt/ptsb-notifier

# копируем содержимое проекта в контейнер
COPY ptsb-notifier/ .

# устанавливаем Python-зависимости
RUN pip install --no-cache-dir -r requirements.txt

# пробрасываем порт
EXPOSE 514

# Стартуем!
CMD ["python", "ptsb-notifier.py"]