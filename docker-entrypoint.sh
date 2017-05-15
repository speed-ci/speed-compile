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

Options:
    -e ARTIFACTORY_URL=string                         URL d'Artifactory (ex: https://artifactory.sln.nc)
    -e ARTIFACTORY_USER=string                        Username d'accès à Artifactory (ex: prenom.nom)
    -e ARTIFACTORY_PASSWORD=string                    Mot de passe d'accès à Artifactory
    -env-file ~/speed.env                             Fichier contenant les variables d'environnement précédentes
    -v \$(pwd):/srv/speed                             Bind mount du répertoire racine de l'application à compiler
    -v /var/run/docker.sock:/var/run/docker.sock      Bind mount de la socket docker pour le lancement de commande docker lors de la compilation
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

ARGS=${ARGS:-""}
DOCKERFILE=${DOCKERFILE:-"Dockerfile.build"}
IMAGE=$ARTIFACTORY_DOCKER_REGISTRY/$PROJECT_NAMESPACE/$PROJECT_NAME:builder

printinfo "ARGS       : $ARGS"
printinfo "DOCKERFILE : $DOCKERFILE"
printinfo "IMAGE      : $IMAGE"
printinfo "PROXY      : $PROXY"
printinfo "NO_PROXY   : $NO_PROXY"

check_docker_env

printstep "Compilation du code source"
OLD_IMAGE_ID=$(docker images -q $IMAGE)
docker build $ARGS  \
             --build-arg http_proxy=$PROXY  \
             --build-arg https_proxy=$PROXY \
             --build-arg no_proxy=$NO_PROXY \
             --build-arg HTTP_PROXY=$PROXY  \
             --build-arg HTTPS_PROXY=$PROXY \
             --build-arg NO_PROXY=$NO_PROXY \
       -f $DOCKERFILE -t $IMAGE .
NEW_IMAGE_ID=$(docker images -q $IMAGE)

if [[ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]]; then
    printstep "Suppression de l'image Docker builder précédente du cache local"
    if [[ -n "$OLD_IMAGE_ID" ]]; then 
        NB_DEPENDENT_CHILD_IMAGES=`docker inspect --format='{{.Id}} {{.Parent}}' $(docker images --filter since=$OLD_IMAGE_ID -q) | wc -l`
        if [[ $NB_DEPENDENT_CHILD_IMAGES -ne 0 ]]; then docker rmi $OLD_IMAGE_ID; fi
    fi
fi

printstep "Vérification des métadonnées du Dockerfile builder"
BUILD_DIR=${BUILD_DIR:-`docker inspect --format '{{ .Config.Env }}' $IMAGE |  tr ' ' '\n' | tr -d ']' | grep BUILD_DIR | sed 's/^.*=//'`}
WORKING_DIR=`docker inspect --format '{{ .Config.WorkingDir }}' $IMAGE`
check_build_env

printstep "Extraction du code compilé"
rm -rf $BUILD_DIR
docker create --name $PROJECT_NAME-builder $IMAGE
docker cp $PROJECT_NAME-builder:$WORKING_DIR/$BUILD_DIR/ ./$BUILD_DIR/
docker rm -f $PROJECT_NAME-builder
