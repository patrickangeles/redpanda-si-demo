BATCH=$(date) ; printf "$BATCH %s\n" {1..1000} | rpk topic produce thelog
