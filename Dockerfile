FROM defradigital/cdp-perf-test-docker:latest

WORKDIR /opt/perftest

COPY bridge-perf ./
COPY run-boundary.sh ./
COPY entrypoint.sh ./
COPY apha-integration-bridge-boundary.jmx ./
COPY apha-integration-bridge-boundary.sample.properties ./
COPY secrets.env.example ./
COPY environments/ ./environments/

RUN chmod +x ./bridge-perf ./run-boundary.sh ./entrypoint.sh

ENV S3_ENDPOINT=https://s3.eu-west-2.amazonaws.com
ENV ENVIRONMENT=dev

ENTRYPOINT ["./entrypoint.sh"]
