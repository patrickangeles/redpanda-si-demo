rpk topic create thelog \
        -c retention.bytes=100000 \
        -c segment.bytes=10000 \
        -c redpanda.remote.read=false \
        -c redpanda.remote.write=false

