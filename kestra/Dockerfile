FROM kestra/kestra:latest-no-plugins

USER root

RUN /app/kestra plugins install \
    io.kestra.plugin:plugin-script-shell:1.9.8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        docker.io \
        bash \
    && rm -rf /var/lib/apt/lists/*