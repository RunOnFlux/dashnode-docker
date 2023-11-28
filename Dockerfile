ARG UBUNTUVER=20.04
FROM ubuntu:${UBUNTUVER}
LABEL com.centurylinklabs.watchtower.enable="true"

RUN mkdir -p /root/.dashcore
RUN mkdir -p /var/log/supervisor
RUN apt-get update && apt-get install -y  tar wget curl pwgen jq supervisor cron git python3-virtualenv
RUN wget https://github.com/dashpay/dash/releases/download/v20.0.1/dashcore-20.0.1-x86_64-linux-gnu.tar.gz -P /tmp
RUN tar xzvf /tmp/dashcore-20.0.1-x86_64-linux-gnu.tar.gz -C /tmp \
&& cp /tmp/dashcore-20.0.1/bin/* /usr/local/bin
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY node_initialize.sh /node_initialize.sh
COPY check-health.sh /check-health.sh
VOLUME /root/.dashcore
RUN chmod 755 node_initialize.sh check-health.sh
EXPOSE 9999
HEALTHCHECK --start-period=5m --interval=2m --retries=5 --timeout=15s CMD ./check-health.sh
ENTRYPOINT ["/usr/bin/supervisord"]
