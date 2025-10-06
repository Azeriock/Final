FROM python:3.6-alpine
LABEL maintainer="Loic" email="loicpierret@live.fr"
WORKDIR /opt
COPY . .
RUN apk update && apk add py3-pip
RUN pip install Flask
EXPOSE 8080
ENTRYPOINT ["python", "app.py"]