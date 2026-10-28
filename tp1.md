Partie 1


1.1 Quelle est la version du moteur Docker ? Quelle est la version de son API ?

 dapi GET /version | jq '{Version, ApiVersion}'

→ HTTP 200
{
  "Version": "29.9.2",
  "ApiVersion": "1.56"
}

1.2 Avec /info, affichez uniquement ces informations, dans un seul objet JSON : le nombre de conteneurs, le nombre de conteneurs en cours d'exécution, le nombre d'images, le système d'exploitation et le nombre de CPU.

dapi GET /info | jq '{Containers, ContainersRunning, Images, OperatingSystem, NCPU}'
→ HTTP 200
{
  "Containers": 0,
  "ContainersRunning": 0,
  "Images": 0,
  "OperatingSystem": "Docker Desktop",
  "NCPU": 12
}

1.3 Toujours avec /info, affichez la mémoire totale de la machine en Gio, arrondie à l'entier. Le champ MemTotal est en octets.

 dapi GET /info | jq '.MemTotal / 1024 / 1024 / 1024 | round'
→ HTTP 200
8

1.4 Listez tous les conteneurs, y compris arrêtés, sous la forme d'une ligne par conteneur : nom   état   image.





Partie 2

2.1 Télécharger l'image.

 dapi POST '/images/create?fromImage=nginx&tag=alpine' | tail -n 3
→ HTTP 200
{"status":"Pulling from library/nginx","id":"alpine"}
{"status":"Digest: sha256:a3554c0d0b48177b1413c26e01f695334428020d9df01243fbae3e11cfd17417"}
{"status":"Status: Image is up to date for nginx:alpine"}

La duréé d'un chargement peut être tres long donc docker envoi des infos de chaques étapes

2.2 Créer le conteneur. Le conteneur s'appelle web-tp1, porte le label tp=api-rest et publie son port 80 sur le port 8088 de la machine.


 dapi POST '/containers/create?name=web-tp1' "$BODY" | jq
→ HTTP 201
{
  "Id": "4285286d4cb8f8384b4dabb8aec44f363b50baea6921306ebdddb4490720f3e1",
  "Warnings": []
}


2.3 Quel code ? Pourquoi la réponse n'a-t-elle pas de corps ? Relancez la même commande : quel code obtenez-vous maintenant, et que signifie-t-il ?

$ dapi POST /containers/web-tp1/start
→ HTTP 204

204 est un code de succes qui signi