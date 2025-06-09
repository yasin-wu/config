FROM jenkins/jenkins:lts

USER root
RUN apt-get update && apt-get install -y wget zip unzip
COPY yq /usr/bin/
RUN chmod +x /usr/bin/yq

USER jenkins