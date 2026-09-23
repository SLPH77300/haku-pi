// Haku Pi — v1.2.0
// Tâche de downsampling « SD light », RENDUE par install.sh (placeholders
// @INFLUX_BUCKET@ / @INFLUX_BUCKET_AGG@) puis créée via `influx task create`.
// Toutes les heures : agrège les points bruts (1/min, bucket 30 j) en
// fenêtres de 10 min vers le bucket long (730 j). Les rafales gardent leur
// MAX (une moyenne les écraserait), tout le reste passe en moyenne.
// La fenêtre -2h recouvre la précédente : réécrire les mêmes horodatages
// est idempotent dans InfluxDB (upsert).
option task = {name: "haku-downsample-10m", every: 1h, offset: 2m}

base = from(bucket: "@INFLUX_BUCKET@") |> range(start: -2h)

base
    |> filter(fn: (r) => r._field == "gust_kn")
    |> aggregateWindow(every: 10m, fn: max, createEmpty: false)
    |> to(bucket: "@INFLUX_BUCKET_AGG@")

base
    |> filter(fn: (r) => r._field != "gust_kn")
    |> aggregateWindow(every: 10m, fn: mean, createEmpty: false)
    |> to(bucket: "@INFLUX_BUCKET_AGG@")
