#!/usr/bin/env bash
set -euo pipefail

SOCK=${DOCKER_SOCK:-/var/run/docker.sock}
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

# api MÉTHODE CHEMIN [JSON]
# Écrit le corps de la réponse dans $BODY et affiche le code HTTP.
api() {
  local method=$1 path=$2 data=${3:-}
  local args=(-sS --unix-socket "$SOCK" -X "$method" -o "$BODY" -w '%{http_code}')
  if [[ -n $data ]]; then
    args+=(-H 'Content-Type: application/json' --data "$data")
  fi
  curl "${args[@]}" "http://localhost$path"
}

die() { echo "erreur : $*" >&2; exit 1; }

# verifier CODE CODE_OK...
# si le code n'est pas bon, on affiche le message de docker et on quitte
verifier() {
  local code=$1
  shift
  for ok in "$@"; do
    if [[ $code == "$ok" ]]; then
      return 0
    fi
  done
  die "HTTP $code : $(jq -r .message "$BODY")"
}

# filtre sur le label du TP, encodé pour l'URL
FILTRE=$(jq -rn '{label: ["tp=api-rest"]} | tojson | @uri')

cmd_ls() {
  code=$(api GET "/containers/json?all=true&filters=$FILTRE")
  verifier "$code" 200

  printf '%-15s %-10s %-20s %s\n' NOM ETAT IMAGE PORTS
  jq -r '.[] | [
    (.Names[0] | ltrimstr("/")),
    .State,
    .Image,
    ([(.Ports // [])[] | select(.PublicPort) | "\(.PublicPort)->\(.PrivatePort)"] | unique | join(","))
  ] | @tsv' "$BODY" | while IFS=$'\t' read -r nom etat image ports; do
    printf '%-15s %-10s %-20s %s\n' "$nom" "$etat" "$image" "$ports"
  done
}

cmd_run() {
  nom=${1:-}
  image=${2:-}
  ports=${3:-}

  if [[ -z $nom || -z $image ]]; then
    die "usage : $0 run NOM IMAGE [PORT_HOTE:PORT_CONTENEUR]"
  fi
  if [[ ! $nom =~ ^[A-Za-z0-9_.-]+$ ]]; then
    die "nom invalide : $nom"
  fi

  # on télécharge l'image seulement si elle n'est pas là
  code=$(api GET "/images/$image/json")
  if [[ $code == 404 ]]; then
    code=$(api POST "/images/create?fromImage=$image")
    verifier "$code" 200
  fi

  # corps de la requête, avec ou sans ports
  if [[ -n $ports ]]; then
    port_hote=${ports%%:*}
    port_conteneur=${ports##*:}
    json=$(jq -n --arg image "$image" --arg hote "$port_hote" --arg cont "$port_conteneur/tcp" '{
      Image: $image,
      Labels: {tp: "api-rest"},
      ExposedPorts: {($cont): {}},
      HostConfig: {PortBindings: {($cont): [{HostPort: $hote}]}}
    }')
  else
    json=$(jq -n --arg image "$image" '{Image: $image, Labels: {tp: "api-rest"}}')
  fi

  code=$(api POST "/containers/create?name=$nom" "$json")
  verifier "$code" 201
  id=$(jq -r .Id "$BODY")

  code=$(api POST "/containers/$id/start")
  verifier "$code" 204

  echo "${id:0:12}"
}

cmd_exec() {
  if [[ $# -lt 2 ]]; then
    die "usage : $0 exec NOM COMMANDE..."
  fi
  nom=$1
  shift

  # les arguments deviennent un tableau JSON
  commande=$(printf '%s\0' "$@" | jq -Rs 'split("\u0000") | .[:-1]')
  json=$(jq -n --argjson cmd "$commande" '{Cmd: $cmd, AttachStdout: true, AttachStderr: true, Tty: true}')

  # 1. créer l'exec
  code=$(api POST "/containers/$nom/exec" "$json")
  verifier "$code" 201
  exec_id=$(jq -r .Id "$BODY")

  # 2. le lancer et afficher ce qu'il renvoie
  code=$(api POST "/exec/$exec_id/start" '{"Detach": false, "Tty": true}')
  verifier "$code" 200
  cat "$BODY"

  # 3. récupérer le code de sortie de la commande
  code=$(api GET "/exec/$exec_id/json")
  verifier "$code" 200
  exit "$(jq -r .ExitCode "$BODY")"
}

cmd_rm() {
  nom=${1:-}
  if [[ -z $nom ]]; then
    die "usage : $0 rm NOM"
  fi

  code=$(api GET "/containers/$nom/json")
  if [[ $code == 404 ]]; then
    echo "$nom : déjà absent"
    return 0
  fi
  verifier "$code" 200

  # on ne touche qu'aux conteneurs du TP
  label=$(jq -r '.Config.Labels.tp // ""' "$BODY")
  if [[ $label != "api-rest" ]]; then
    die "$nom n'est pas un conteneur du TP"
  fi

  code=$(api POST "/containers/$nom/stop?t=5")
  verifier "$code" 204 304

  code=$(api DELETE "/containers/$nom")
  verifier "$code" 204

  echo "$nom : supprimé"
}

cmd_clean() {
  code=$(api GET "/containers/json?all=true&filters=$FILTRE")
  verifier "$code" 200
  noms=$(jq -r '.[].Names[0] | ltrimstr("/")' "$BODY")

  if [[ -z $noms ]]; then
    echo "aucun conteneur du TP"
    return 0
  fi

  for nom in $noms; do
    code=$(api DELETE "/containers/$nom?force=true")
    verifier "$code" 204
    echo "$nom : supprimé"
  done
}

case ${1:-} in
  ls|run|exec|rm|clean) cmd=$1; shift; "cmd_$cmd" "$@" ;;
  *) echo "usage : $0 {ls|run|exec|rm|clean} …" >&2; exit 2 ;;
esac
