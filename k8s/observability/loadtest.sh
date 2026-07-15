#!/usr/bin/env bash
# Preuves démo section C : montée en charge -> HPA, et mesure d'indispo sur kill pod.
# ponytail: cible le ClusterIP en interne (pas d'ingress), boucle wget naïve -- suffisant
#           pour la démo ; si le HPA ne monte pas, augmenter LOADERS=8.
set -euo pipefail

NS=green-trade
SVC=green-trade-catalog-api          # Service ClusterIP :80 -> :4000
PATH_="${PATH_:-/health}"            # endpoint ciblé (ex: /api/products pour + de CPU)
LOADERS=${LOADERS:-8}                 # nb de pods générateurs
WORKERS=${WORKERS:-30}               # requêtes concurrentes PAR pod (LOADERS*WORKERS au total)
DURATION=${DURATION:-120}            # durée de la charge (s)

load() {
  echo ">> $LOADERS pods x $WORKERS workers = $((LOADERS*WORKERS)) requêtes concurrentes sur http://$SVC$PATH_ pendant ${DURATION}s"
  for i in $(seq 1 "$LOADERS"); do
    kubectl -n "$NS" run "loadgen-$i" --image=busybox --restart=Never -- \
      /bin/sh -c "end=\$(( \$(date +%s) + $DURATION )); w=0; while [ \$w -lt $WORKERS ]; do ( while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://$SVC$PATH_ >/dev/null 2>&1; done ) & w=\$((w+1)); done; wait" >/dev/null
  done
  echo ">> Suivi du HPA (Ctrl-C pour arrêter, puis '$0 clean') :"
  kubectl -n "$NS" get hpa -w
}

resilience() {
  local secs=${1:-30}
  echo ">> Sonde de dispo sur $SVC pendant ${secs}s."
  echo ">> Pendant ce temps, dans un AUTRE terminal, tuez un pod :"
  echo "   kubectl -n $NS delete pod \$(kubectl -n $NS get pod -l app.kubernetes.io/component=catalog-api -o name | head -1)"
  kubectl -n "$NS" run probe --image=busybox --restart=Never --rm -i --quiet -- \
    /bin/sh -c "
      ok=0; ko=0; end=\$(( \$(date +%s) + $secs ));
      while [ \$(date +%s) -lt \$end ]; do
        if wget -q -T 2 -O- http://$SVC/health >/dev/null 2>&1; then ok=\$((ok+1)); else ko=\$((ko+1)); fi
        sleep 0.2
      done
      total=\$((ok+ko));
      echo \"Requêtes: \$total | OK: \$ok | KO: \$ko\";
      [ \$total -gt 0 ] && echo \"Indisponibilité mesurée: \$(( ko*100/total ))%\"
    "
}

clean() {
  for i in $(seq 1 16); do kubectl -n "$NS" delete pod "loadgen-$i" --ignore-not-found >/dev/null 2>&1 || true; done
  echo ">> Générateurs nettoyés."
}

case "${1:-}" in
  load)       load ;;
  resilience) resilience "${2:-30}" ;;
  clean)      clean ;;
  *) echo "Usage: $0 {load | resilience [secondes] | clean}"; exit 1 ;;
esac
