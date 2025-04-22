FROM debian:12
RUN apt-get update
RUN apt-get install  -y ca-certificates curl wget mariadb-client iputils-ping zip cron
RUN rm -rf /var/lib/apt/lists/*

RUN curl https://dl.min.io/client/mc/release/linux-amd64/mc \
  --create-dirs \
  -o $HOME/minio-binaries/mc

RUN chmod +x $HOME/minio-binaries/mc

RUN mkdir /backup/
COPY backup.sh /backup/backup.sh
RUN chmod +x /backup/backup.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh