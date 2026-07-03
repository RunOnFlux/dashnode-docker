FROM ubuntu:22.04
LABEL com.centurylinklabs.watchtower.enable="true"

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget curl jq pwgen supervisor cron tar gzip xz-utils bzip2 unzip procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /root/.dashcore /var/log/supervisor

# Install Dash Core. Binaries live under dashcore-<ver>/bin/ in the tarball.
# PIN the CURRENT mainnet release. v20.0.4 was 3 majors stale and below the enforced
# minimum protocol version -> PoSe-banned / forked off mainnet. 23.1.7 verified 200.
ARG DASH_VERSION=23.1.7
RUN set -eux; \
    wget -qO /tmp/dash.tgz \
      "https://github.com/dashpay/dash/releases/download/v${DASH_VERSION}/dashcore-${DASH_VERSION}-x86_64-linux-gnu.tar.gz"; \
    tar xzf /tmp/dash.tgz -C /tmp; \
    cp /tmp/dashcore-${DASH_VERSION}/bin/dashd /tmp/dashcore-${DASH_VERSION}/bin/dash-cli /usr/local/bin/; \
    chmod +x /usr/local/bin/dashd /usr/local/bin/dash-cli; \
    rm -rf /tmp/dash.tgz /tmp/dashcore-${DASH_VERSION}

COPY coin.env /usr/local/bin/coin.env
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY node_initialize.sh /usr/local/bin/node_initialize.sh
COPY mn-autoheal.sh /usr/local/bin/mn-autoheal.sh
COPY check-health.sh /usr/local/bin/check-health.sh
RUN chmod 755 /usr/local/bin/node_initialize.sh /usr/local/bin/mn-autoheal.sh \
              /usr/local/bin/check-health.sh /usr/local/bin/coin.env

VOLUME /root/.dashcore
EXPOSE 9999
HEALTHCHECK --start-period=20m --interval=10m --retries=3 --timeout=15s CMD /usr/local/bin/check-health.sh
ENTRYPOINT ["/usr/bin/supervisord"]
