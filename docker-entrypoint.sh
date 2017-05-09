#!/bin/bash
set -e

ARGS=${ARGS:-""}
DOCKERFILE=${DOCKERFILE:-"Dockerfile.build"}
IMAGE=$ARTIFACTORY_DOCKER_REGISTRY/$PROJECT_NAMESPACE/$PROJECT_NAME:build

check_docker_env () {
    if [[ ! -f $DOCKERFILE ]];then
        printerror "Le fichier $DOCKERFILE n’est pas présent, il doit se trouver à la racine du projet"
        exit 1
    fi
}

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
check_docker_env

printstep "Compilation du code source"
docker build $ARGS --build-arg http_proxy=$PROXY -f $DOCKERFILE -t $IMAGE .

printstep "Vérification des métadonnées du Dockerfile builder"
BUILD_DIR=${BUILD_DIR:-`docker inspect --format '{{ .Config.Env }}' $IMAGE |  tr ' ' '\n' | tr -d ']' | grep BUILD_DIR | sed 's/^.*=//'`}
WORKING_DIR=`docker inspect --format '{{ .Config.WorkingDir }}' $IMAGE`
check_build_env

printstep "Extraction du code compilé"
rm -rf $BUILD_DIR
docker create --name $PROJECT_NAME-build $IMAGE
docker cp $PROJECT_NAME-build:$WORKING_DIR/$BUILD_DIR/ ./$BUILD_DIR/
docker rm -f $PROJECT_NAME-build
