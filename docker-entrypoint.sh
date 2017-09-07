#!/bin/bash
set -e

source /init.sh

function help () {
# Using a here doc with standard out.
cat <<-END

Usage: docker run [OPTIONS] docker-artifactory.sln.nc/speed/speed-compile

Compiler le code source de l'application du répertoire courant
Le builder utilisé doit être défini dans un fichier Dockerfile.build à la racine du projet
Les variables suivantes doivent être renseignée dans le fichier Dockerfile.build:
    - WORKING_DIR   : le répertoire de travail du builder
    - BUILD_DIR     : le répertoire de destination du code compilé 
L'action de compiler consiste à prendre du code source en entrée et générer une image contenant l'environnement de compilation et le code compilé en sortie.
Le répertoire du code compilé de l'image du builder est ensuite copiée dans le répertoire BUILD_DIR à la racine du projet

Options:
    -e ARTIFACTORY_URL=string                         URL d'Artifactory (ex: https://artifactory.sln.nc)
    -e ARTIFACTORY_USER=string                        Username d'accès à Artifactory (ex: prenom.nom)
    -e ARTIFACTORY_PASSWORD=string                    Mot de passe d'accès à Artifactory
    -e NO_CACHE=boolean                               Désactiver l'utilisation du cache lors du docker build (default: false)
    --env-file ~/speed.env                             Fichier contenant les variables d'environnement précédentes
    -v \$(pwd):/srv/speed                              Bind mount du répertoire racine de l'application à compiler
    -v /var/run/docker.sock:/var/run/docker.sock      Bind mount de la socket docker pour le lancement de commandes docker lors de la compilation
END
}

while [ -n "$1" ]; do
    case "$1" in
        -h | --help | help)
            help
            exit
            ;;
    esac 
done

check_build_env () {
    if [[ -z $BUILD_DIR ]];then
        printerror "La variable BUILD_DIR n'est pas présente, elle doit être précisée dans le fichier $DOCKERFILE (ex: dist pour js, target pour java)"
        exit 1
    fi
    if [[ -z $WORKING_DIR ]];then
        printerror "La variable WORKING_DIR n'est pas présente, elle doit être précisée dans le fichier $DOCKERFILE (ex: /usr/src/ap pour js)"
        exit 1
    fi    
}

printmainstep "Compilation de l'application par Docker Builder Pattern"
printstep "Vérification des paramètres d'entrée"
init_env

DOCKERFILE=${DOCKERFILE:-"Dockerfile.build"}
IMAGE=$ARTIFACTORY_DOCKER_REGISTRY/$PROJECT_NAMESPACE/$PROJECT_NAME:builder
NO_CACHE=${NO_CACHE:-"false"}
if [[ "$NO_CACHE" == "true" ]]; then ARGS="--no-cache"; fi

printinfo "DOCKERFILE : $DOCKERFILE"
printinfo "IMAGE      : $IMAGE"
printinfo "PROXY      : $PROXY"
printinfo "NO_PROXY   : $NO_PROXY"
printinfo "NO_CACHE   : $NO_CACHE"

check_docker_env

printstep "Compilation du code source"
docker login -u $ARTIFACTORY_USER -p $ARTIFACTORY_PASSWORD $ARTIFACTORY_DOCKER_REGISTRY
OLD_IMAGE_ID=$(docker images -q $IMAGE)
docker build $ARGS  \
             --build-arg http_proxy=$PROXY  \
             --build-arg https_proxy=$PROXY \
             --build-arg no_proxy=$NO_PROXY \
             --build-arg HTTP_PROXY=$PROXY  \
             --build-arg HTTPS_PROXY=$PROXY \
             --build-arg NO_PROXY=$NO_PROXY \
             --build-arg ARTIFACTORY_URL=$ARTIFACTORY_URL \
             --build-arg ARTIFACTORY_USER=$ARTIFACTORY_USER \
             --build-arg ARTIFACTORY_PASSWORD=$ARTIFACTORY_PASSWORD \
       -f $DOCKERFILE -t $IMAGE .
NEW_IMAGE_ID=$(docker images -q $IMAGE)

if [[ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]]; then
    printstep "Suppression de l'image Docker builder précédente du cache local"
    if [[ -n "$OLD_IMAGE_ID" ]]; then docker rmi -f $OLD_IMAGE_ID || true; fi
fi

printstep "Vérification des métadonnées du Dockerfile builder"
BUILD_DIR=${BUILD_DIR:-`docker inspect --format '{{ .Config.Env }}' $IMAGE |  tr ' ' '\n' | tr -d ']' | grep BUILD_DIR | sed 's/^.*=//'`}
WORKING_DIR=`docker inspect --format '{{ .Config.WorkingDir }}' $IMAGE`
check_build_env

printstep "Extraction du code compilé"
CONTAINER_NAME=$PROJECT_NAMESPACE-$PROJECT_NAME-builder
printinfo "CONTAINER_NAME   : $CONTAINER_NAME"
ls -la $BUILD_DIR
rm -rf $BUILD_DIR
ls -la $BUILD_DIR
docker rm -f $CONTAINER_NAME || true
docker create --name $CONTAINER_NAME $IMAGE
docker cp $CONTAINER_NAME:$WORKING_DIR/$BUILD_DIR/ ./$BUILD_DIR/
docker rm -f $CONTAINER_NAME || true
