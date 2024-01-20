ARG UBUNTUVER=20.04
FROM ubuntu:${UBUNTUVER}
LABEL com.centurylinklabs.watchtower.enable="true"

ENV DASH_VERSION="20.0.4"
RUN mkdir -p /root/.dashcore
RUN mkdir -p /var/log/supervisor
RUN apt-get update && apt-get install -y  tar wget curl pwgen jq supervisor cron git python3-virtualenv
RUN wget https://github.com/dashpay/dash/releases/download/v${DASH_VERSION}/dashcore-${DASH_VERSION}-x86_64-linux-gnu.tar.gz -P /tmp && \
    tar xzvf /tmp/dashcore-${DASH_VERSION}-x86_64-linux-gnu.tar.gz -C /tmp && \
    cp /tmp/dashcore-${DASH_VERSION}/bin/* /usr/local/bin && \
    rm -rf /tmp/*
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY node_initialize.sh /node_initialize.sh
COPY check-health.sh /check-health.sh
COPY key.sh /key.sh
VOLUME /root/.dashcore
RUN chmod 755 node_initialize.sh check-health.sh key.sh
EXPOSE 9999
HEALTHCHECK --start-period=5m --interval=5m --retries=5 --timeout=15s CMD ./check-health.sh
ENTRYPOINT ["/usr/bin/supervisord"]
