# Gada-Electronics-Config

## Application monitoring

The `Gada checkout health` Grafana dashboard shows failed checkout attempts by reason, request p95 latency, and ready app pods for each environment. `GadaCheckoutFailuresHigh` warns when at least five non-empty-cart checkout failures occur in five minutes for two minutes; existing alerts cover slow requests and app availability. Review failure reasons in the dashboard before investigating app logs or inventory changes.