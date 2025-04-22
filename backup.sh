#!/bin/bash
source .env

#s3
$HOME/minio-binaries/mc alias set my $S3_ENDPOINT $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY

# Текущая дата и время в формате YYYY-MM-DD_HH-MM-SS с учетом московского времени
DATE=$(TZ='Europe/Moscow' date +%F_%H-%M)

# Создаем директорию для бэкапов, если её нет
mkdir -p "$BACKUP_DIR"

# Функция для бэкапа одной базы данных
backup_database() {
    local db=$1
    local backup_file="$BACKUP_DIR/${db}_backup_$DATE.sql"
    local zip_file="$BACKUP_DIR/${db}_backup_$DATE.zip"

    # Выполняем бэкап
    echo "Начинаем создание бэкапа для базы данных $db." >/proc/1/fd/1
    if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -h "$MYSQL_HOST" "$db" --single-transaction --opt --quote-names > "$backup_file"; then
        echo "Бэкап базы данных $db создан успешно: $backup_file." >/proc/1/fd/1
    else
        echo "Ошибка создания бэкапа базы данных $db." >/proc/1/fd/1
        return 1
    fi

    # Проверка структуры файла бэкапа
BEGIN=$(head -n 10 "$backup_file" | grep -c 'dump')
END=$(tail -n 1 "$backup_file" | grep -c '^-- Dump completed')    

    if [ "$BEGIN" -eq 1 ] && [ "$END" -eq 1 ]; then
        echo "Бэкап базы данных $db проверен." >/proc/1/fd/1
        if zip -j -P "$ENCRYPTION_PASSWORD" "$zip_file" "$backup_file"; then
            echo "Файл $backup_file успешно заархивирован в $zip_file." >/proc/1/fd/1
            rm "$backup_file"
        else
            echo "Ошибка архивации бэкапа базы данных $db." >/proc/1/fd/1
            return 1
        fi
    else
        echo "Ошибка проверки бэкапа базы данных $db: структура файла повреждена." >/proc/1/fd/1
        rm "$backup_file"
        return 1
    fi

    # Загрузка на S3
    echo "Загружаем бэкап $zip_file на S3: $S3_BUCKET." >/proc/1/fd/1
    if $HOME/minio-binaries/mc cp "$zip_file" "my/$S3_BUCKET/$S3_FOLDER"; then
        echo "Бэкап базы данных $db успешно загружен на S3." >/proc/1/fd/1
    else
        echo "Ошибка загрузки бэкапа $zip_file на S3." >/proc/1/fd/1
        return 1
    fi


############Сравнение размеров
  local_size=$($HOME/minio-binaries/mc stat "$zip_file" | awk '/Size/ {print $3}' | sed 's/[^0-9]*//g')
  s3_size=$($HOME/minio-binaries/mc stat "my/$S3_BUCKET$S3_FOLDER$(basename "$zip_file")" | awk '/Size/ {print $3}' | sed 's/[^0-9]*//g')

if [ "$local_size" -eq "$s3_size" ]; then
    echo "Размеры файла на локальной машине и на S3 совпадают Локальный файл: $local_size, файл на S3: $s3_size." >/proc/1/fd/1
    rm "$zip_file"
else
    echo "Ошибка: размеры файлов не совпадают. Локальный файл: $local_size, файл на S3: $s3_size."  >/proc/1/fd/1
    rm "$zip_file"
    return 1
fi
############Сравнение размеров


}

# Цикл по базам данных
for db in $DATABASES; do
    backup_database "$db" || {
    echo "Не удалось создать бэкап для базы данных $db."
    }
done

# Удаление старых бэкапов с S3
echo "Удаление старых бэкапов (старше ${SAVE_TIME_HOUR}) на S3."
$HOME/minio-binaries/mc find "my/$S3_BUCKET$S3_FOLDER" --name "*_backup_*.zip" --older-than ${SAVE_TIME_HOUR} --exec "$HOME/minio-binaries/mc rm {}" || {
    echo "Ошибка при удалении старых бэкапов." >/proc/1/fd/1
}