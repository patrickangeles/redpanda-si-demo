
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
You should see something like this.

```
$ tree volumes
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

## Produce some data

```bash
BATCH=$(date) ; printf "$BATCH %s\n" {1..1000} | rpk topic produce thelog
```

Repeat this a few times, while checking the directory structure with `tree volumes`.
After producing some data, you should see something that looks like this.

```
$ tree volumes/redpanda/data/kafka 
volumes/redpanda/data/kafka
└── thelog
    └── 0_3
        ├── 0-1-v1.base_index
        ├── 0-1-v1.log
        ├── 2001-1-v1.base_index
        ├── 2001-1-v1.log
        ├── 4001-1-v1.base_index
        ├── 4001-1-v1.log
        └── archival_metadata.snapshot
```
Consume some data, from the earliest available offset.

```bash
rpk topic consume thelog -n 3
```
Output should look something like this.

```
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:19 EDT 2022 1",
  "timestamp": 1651156159604,
  "partition": 0,
  "offset": 0
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:19 EDT 2022 2",
  "timestamp": 1651156159604,
  "partition": 0,
  "offset": 1
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:19 EDT 2022 3",
  "timestamp": 1651156159604,
  "partition": 0,
  "offset": 2
}
```

Keep producing more data, until the offset exceeds ~12000 or so.
Have a look at the directory structure. You'll notice that the first log segment `0-1-v1.log` is now gone.

```
$ tree volumes/redpanda/data/kafka
volumes/redpanda/data/kafka
└── thelog
    └── 0_3
        ├── 10001-1-v1.base_index
        ├── 10001-1-v1.log
        ├── 12001-1-v1.base_index
        ├── 12001-1-v1.log
        ├── 2001-1-v1.base_index
        ├── 2001-1-v1.log
        ├── 4001-1-v1.base_index
        ├── 4001-1-v1.log
        ├── 6001-1-v1.base_index
        ├── 6001-1-v1.log
        ├── 8001-1-v1.base_index
        ├── 8001-1-v1.log
        ├── archival_metadata.snapshot
        └── snapshot
```
When you consume from the topic, you will no longer see data from the first segment.
Here, our consumer sees offset 2000 as the earliest available.

```
$ rpk topic consume thelog -n 3
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 1",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2000
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 2",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2001
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 3",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2002
}
```

## Enable Shadow Indexing

Now let's turn on Shadow Indexing

```bash
rpk topic alter-config thelog -s redpanda.remote.read=true
rpk topic alter-config thelog -s redpanda.remote.write=true
```

After a few seconds, then you'll notice that log segments have been uploaded and now show up on MinIO.

```
$ tree volumes/minio/data
volumes/minio/data
└── redpanda
    ├── 1ebedfeb
    │   └── kafka
    │       └── thelog
    │           └── 0_3
    │               └── 2001-1-v1.log.1
    ├── 237ffc6f
    │   └── kafka
    │       └── thelog
    │           └── 0_3
    │               └── 12001-1-v1.log.1
    ├── 371013e1
    │   └── kafka
    │       └── thelog
    │           └── 0_3
    │               └── 4001-1-v1.log.1
    ├── 3b4f5905
    │   └── kafka
    │       └── thelog
    │           └── 0_3
    │               └── 6001-1-v1.log.1
    ├── 9805bcb1
    │   └── kafka
    │       └── thelog
    │           └── 0_3
    │               └── 8001-1-v1.log.1
    ├── a0000000
    │   └── meta
    │       └── kafka
    │           └── thelog
    │               └── 0_3
    │                   └── manifest.json
    ├── b0000000
    │   └── meta
    │       └── kafka
    │           └── thelog
    │               └── topic_manifest.json
    └── f8ae70fa
        └── kafka
            └── thelog
                └── 0_3
                    └── 10001-1-v1.log.1
```

Now, let's produce more data such that the oldest log segments (starting with offset 2000) start to disappear.

```bash
BATCH=$(date) ; printf "$BATCH %s\n" {1..1000} | rpk topic produce thelog
```

Repeat that a few times until some segments get cleaned up (deleted) from the Redpanda data dir.
Here, the segments `2001-1-v1.log` and `4001-1-v1.log` have been deleted.

```
$ tree volumes/redpanda/data/kafka
volumes/redpanda/data/kafka
└── thelog
    └── 0_2
        ├── 10001-1-v1.base_index
        ├── 10001-1-v1.log
        ├── 12001-1-v1.base_index
        ├── 12001-1-v1.log
        ├── 14007-1-v1.base_index
        ├── 14007-1-v1.log
        ├── 16008-1-v1.base_index
        ├── 16008-1-v1.log
        ├── 6001-1-v1.base_index
        ├── 6001-1-v1.log
        ├── 8001-1-v1.base_index
        ├── 8001-1-v1.log
        ├── archival_metadata.snapshot
        └── snapshot
```

However, those segments are still in S3, so we can still consume from those offsets.

```
$ rpk topic consume thelog -n 3
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 1",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2000
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 2",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2001
}
{
  "topic": "thelog",
  "value": "Thu Apr 28 10:29:21 EDT 2022 3",
  "timestamp": 1651156161377,
  "partition": 0,
  "offset": 2002
}
```
