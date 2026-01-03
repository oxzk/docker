# 🖥️ Ubuntu

[Ubuntu Desktop](https://ubuntu.com/desktop) is a popular open-source operating system designed for personal computers and laptops. It offers a user-friendly interface and a wide range of software options, making it suitable for both new and experienced users.

## Setup

```
docker run -d \
  --name=webtop \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -p 3000:3000 \
  -p 3001:3001 \
  -v $(pwd)/webtop:/config \
  --shm-size="2gb" \
  --restart unless-stopped \
  oxzk/webtop:latest
```
