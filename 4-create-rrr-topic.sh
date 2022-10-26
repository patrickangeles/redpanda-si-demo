set -x
rpk topic create thelog \
        -c redpanda.remote.readreplica=redpanda \
        --brokers localhost:9192

