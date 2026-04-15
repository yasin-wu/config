FROM jenkins/jenkins:2.558

USER root
RUN apt-get update && apt-get install -y wget zip unzip
COPY yq /usr/bin/
RUN chmod +x /usr/bin/yq
COPY helm /usr/bin/
RUN chmod +x /usr/bin/helm

USER jenkins