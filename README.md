
# Redpanda Tiered Storage Demo

## Pre-requisites

To go through this demo, you will need:

* Docker
* `rpk` - Redpanda CLI
* `mc` - MinIO Console
* `tree` - Optional, for hierarchical directory listing

### Installing Pre-requisites on MacOS

```bash
brew install redpanda-data/tap/redpanda
brew install minio/stable/mc
brew install tree
```
 
## Overview of `docker-compose.yml`

```yaml
version: "3.9"
   
services:
  minio:
    image: quay.io/minio/minio
    command: server --console-address ":9001" /data
    ports:
      - 9000:9000
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
      MINIO_SERVER_URL: "http://minio:9000"
      MINIO_REGION_NAME: local
      MINIO_DOMAIN: minio
    volumes:
      - ./volumes/minio/data:/data

  redpanda:
    image: docker.vectorized.io/vectorized/redpanda:v21.11.12
    command:
      - redpanda start
      - --smp 1
      - --memory 512M
      - --reserve-memory 0M
      - --overprovisioned
      - --node-id 0
      - --set redpanda.auto_create_topics_enabled=false
      - --kafka-addr INSIDE://0.0.0.0:9094,OUTSIDE://0.0.0.0:9092
      - --advertise-kafka-addr INSIDE://redpanda:9094,OUTSIDE://localhost:9092
      - --set redpanda.cloud_storage_enabled=true
      - --set redpanda.cloud_storage_region=local
      - --set redpanda.cloud_storage_access_key=minio
      - --set redpanda.cloud_storage_secret_key=minio123
      - --set redpanda.cloud_storage_api_endpoint=minio
      - --set redpanda.cloud_storage_api_endpoint_port=9000
      - --set redpanda.cloud_storage_disable_tls=true
      - --set redpanda.cloud_storage_bucket=redpanda
      - --set redpanda.cloud_storage_segment_max_upload_interval_sec=30
    ports:
      - 9092:9092
      - 9644:9644
    volumes:
      - ./volumes/redpanda/data:/var/lib/redpanda/data
```

## Start up the Docker Compose

```bash
docker compose up -d
```

## Set up Minio 

Create an alias and an S3 bucket for Redpanda

```bash
mc alias set local http://localhost:9000 minio minio123
mc mb local/redpanda
```

## Create a topic 

You can see what the current directory structure looks like with the `tree` command.

```bash
tree volumes
```
Create the topic. For now, we want Shadow Indexing disabled.

```bash
rpk topic create thelog \
        -c retention.bytes=100000 \
        -c segment.bytes=10000 \
        -c redpanda.remote.read=false \
        -c redpanda.remote.write=false
```

Look again to see that the directory structure has changed with `tree volumes`.

## Produce some data

```bash
BATCH=$(date) ; printf "$BATCH %s\n" {1..1000} | rpk topic produce thelog
```

Repeat this a few times, while checking the directory structure with `tree volumes`.
After producing some data, you should see something that looks like this.

```
volumes
├── minio
│   └── data
│       └── redpanda
└── redpanda
    └── data
        ├── kafka
        │   └── thelog
        │       └── 0_3
        │           ├── 0-1-v1.base_index
        │           ├── 0-1-v1.log
        │           ├── 2001-1-v1.base_index
        │           ├── 2001-1-v1.log
        │           ├── 4001-1-v1.base_index
        │           ├── 4001-1-v1.log
        │           ├── 6001-1-v1.base_index
        │           ├── 6001-1-v1.log
        │           └── archival_metadata.snapshot
        ├── pid.lock
        ├── redpanda
        │   ├── controller
        │   │   └── 0_0
        │   │       ├── 0-1-v1.base_index
        │   │       └── 0-1-v1.log
        │   └── kvstore
        │       └── 0_0
        │           ├── 0-0-v1.base_index
        │           └── 0-0-v1.log
        ├── supervisord.log
        └── wasm_engine.log
```

## Enable Shadow Indexing for our topic

```bash
rpk topic alter-config thelog \
        -s redpanda.remote.read=true \
        -s redpanda.remote.write=true
```

