# Minikube, setup sous Linux pour une application "WEB" (NGINX + PHP-FPM)

Télécharger et installer minikube

## Activer Ingress Controller

```
minikube addons enable ingress
```
## Credentials pour Amazon ECR
Afin de pouvoir pull les images Docker hébergées sur AWS le plus simple est de configurer et activer l'addon:

```
minikube addons disable registry-creds
kubectl -n kube-system create secret generic registry-creds-ecr 
minikube addons configure registry-creds
minikube addons enable registry-creds

minikube ssh
apt update
apt install net-tools #route cmd
apt install  nfs-common
```

                        

## Montage NFS

Afin de partager le code source entre son host et minikube il est conseillé de monter un partage NFS

Pour cela en local et en root:

```
mkdir -p /opt/passman/data
mkdir -p /opt/passman/src

vim /etc/fstab 
=> ou "/home/clem/dev/" correspond aux sources de votre projet

/home/clem/dev/  /opt/passman/src    bind bind,nofail 0 0
/home/clem/data-dev/     /opt/passman/data   bind bind,nofail 0 0

puis: mount -a


```

```
vim /etc/exports =>  

/opt/passman/src/  *(rw,sync,no_subtree_check,no_root_squash,insecure)
/opt/passman/data/ *(rw,sync,no_subtree_check,no_root_squash,insecure)

```

```
sudo exportfs -rv
systemctl restart nfs-kernel-server
```
On récupère ensuite l'IP de notre host avec laquelle minikube peut communiquer:
```
minikube ssh "route -n | grep ^0.0.0.0 | awk '{ print \$2 }'"
```
=> dans ce cas 10.0.2.2

Pour automatiser et modifier le host de minikube:
```
ETCPATH=~/.minikube/files/etc && mkdir -p $ETCPATH && MKUBEHOST=$( minikube ssh "route -n | grep ^0.0.0.0 | awk '{ print \$2 }'" ) && cat > $ETCPATH/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       minikube
${MKUBEHOST:: -1}     nfsserver
EOF

minikube stop && minikube start

```

Il faut ensuite récupérer le repository "infra-docker" de Sébastien pour avoir le NFS provisionner  (Dans /opt/passman/src)

``` 
git clone git@github.com:passmanSA/infra-docker.git
```

Puis un apply du provisionner NFS:

```
cd infra-docker/Notes-SR/helm/nfs-client-provisioner$ kubectl apply -f resultat.yaml 
```


Il faut aussi un service MYSQL avec la base wifipass

/!\ sur dernière version MYSQL peut planter (erreur 5)
Dans ce cas, il faut désactiver dans le values_dev.yaml le mountNFS, et activer le mount PVC.
(import des data manuellement depuis workbench + import des utilisateurs qui se trouvent dans export)

```
git clone git@github.com:passmanSA/mysql-staging.git

/opt/passman/src/mysql-staging$ make helm-install
make helm install
```
Avec l'absence de message d'erreur, ont peux supposer que l'installation c'est bien dérouler. La vérification se fera plus tard.

Pour que le hot-reloading soit réactif il faut désactiver le cache NFS de minikube.
Il faut copier le fichier

'infra-docker/Notes-SR/helm/simple-mysql/nfsmount.conf' dans => .minikube/files/etc/ 

(et redemarrer minikube ensuite via ```minikube stop && minikube start```)


## Deploy de l'app 

retourner au repertoire source ```/opt/passman/src```

Cloner le repo via ``` git clone https://github.com/passmanSA/wifi-v5-api-public.git ``` dans /opt/passman/src

Dans le dossier wifi-v5-api-public executez : ```make create-secret &&  make helm-install```

Ajoutez le lien minikube dans le fichier hosts : 

* Executer ``` minikube ip ``` pour avoir l'ip de minikube

* Puis executez ``` sudo vim /etc/hosts ``` et y ajouter l'ip_de_minikube minikube (ex: 192.168.99.100 minikube) 

* Et enfin e ``` sudo service networking restart ``` pour redémarer le service

*Il est alors possible de vérifier la configuration en se rendant sur http://minikube/dev/public-access-api/api/portal-configuration/testv4*

**Verification de la base de donnée**
Il est alors possible de vérifier la connextion sql manuellement via :

* ```make shell``` 

* ```mysql -h mysql-wifipass-svc-mysql.wifipass-mysql -u root -ppassword ```

* Si l'installation sql c'est executer correctement en faisant un ``` show databases ``` wifipass devrais apparaitre

### Cas erreur 503

En cas d'erreur, il est possible de vérifier l'état du pods via ``` kubectl get pods -n wifipass-portails ```.
Si Ready est a 0/1,le pods n'est pas près.

il est possible d'établire un diagnostique du problème via les commandes : 

*Note : ici wifi-v5-api-public-deploy-php-7699464567-76xq9 = id du pods retourné par ``` kubectl get pods -n wifipass-portails ```*

* la commande ``` kubectl describe pods wifi-v5-api-public-deploy-php-7699464567-76xq9 -n wifipass-portails wifi-v5-api-public-deploy-php-7699464567-76xq9 ``` retournera tout les informations du pods dont les erreurs. 

* la commande ``` kubectl logs wifi-v5-api-public-deploy-php-7699464567-76xq9 -n wifipass-portails ``` 

<ins>Dans le cas ou l'une erreur est dû au montage nfs :</ins>

  * Se connecter a minikube via ``` minikube ssh```
  
  * Vérifier le hosts via ``` cas /etc/hosts ```
  
  * Vérifier hors minikube l'adresse de la machine via via la commande ``` minikube ssh "route -n | grep ^0.0.0.0 | awk '{ print \$2 }'" ```
  
  * Vérifier que l'adresse soit dans le fichier ~/.minikube/files/etc/hosts et l'ajouter si besoin via ```vim ~/.minikube/files/etc/hosts ```
  
  * Modifiez la ligne **nfsserver** sur le minikube via ``` vim /etc/hosts ```
  
  * Redémarrez minikube via ``` minikube stop && minikube start ```

  * Validez le bon fonctionnement du pods via ```minikube stop && minikube start``` et en rafrechisant la page web
  
  
### Cas erreur 500 :

Il est possible d'avoir des informations via ``` kubectl logs ```

<ins>Dans le cas d'erreur liée au vendor il faut :</ins>

  * se connecter sur le pods via ``` make shell ```
  
  * installer les vendor  via ``` composer install ```
  
<ins>Dans le cas d'une erreur **SQLSTATE[HY000] [2002] php_network_getaddresses: getaddrinfo failed: Name does not resolve** : <ins>
  
  * executer ``` kubectl get svc -n wifipass-mysql ``` pour obtenir les informations du pods dont son nom, ici **simple-mysql-svc-mysql**
  
  * vérifier (``` cat ```) et remplacer (```vim```) la variable **DATABASE_URL** dans le fichier .env  dans ``` /opt/passman/src/wifi-v5-api-public/.env ```
  
  * remplacer la valeur de la façon suivant : DATABASE_URL=mysql://root:password@**simple-mysql-svc-mysql.wifipass-mysql**:3306/wifipass
  
  * rafraichire la page web
  
  *Il est possible de vérifier la connextion sql manuellement via ```make shell``` puis ```mysql -h simple-mysql-svc-mysql -u root -ppassword ```
  
<ins>
  Dans le cas d'une erreur de database type : **SQLSTAT[HY000][149] Unknow database wifipass** effacer le service mysql-wifipass-svc-mysql et ces fichiers 
  </ins>
 
 * supprimer le service : ```helm uninstall -n wifipass-mysql wifipass-mysql``` 
 
 * verifier qu'il a bien était supprimer : ```kubectl get pods -n wifipass-mysql```
 
 * Si le service est toujour présent : ``` kubectl delete all --all -n wifipass-mysql ```
 
 * Eteindre minikube : ``` minikube stop ```
 
 * Effacer les data dans /opt/passman/data : ``` sudo rm -rf opt/passman/data/archived-* ``` et ``` sudo rm -rf opt/passman/data/wifipass-*```
 
 * redemarer minikube : ``` minikube start ```
 
 * Allez dans le dossier test-mysql pour y faire un ``` make helm-install ```
 
 * le bon fonctionnement peux être vérifiabe via rafraichisement de la page ou connexion a la base de donnée
 
 <ins> Dans le cas d'une erreur SQL type select </ins>
 
 * Connectez vous a la base de donnée
 * Après avoir selectionner la base wifipass executer les commandes se trouvant dans **/opt/passman/src/wifi-v5-api-public/data/evolSQLV5.txt**

## Connexion MYSQL en local 
Pour se connecter à la BDD depuis l'host (MySQL Workbench par exemple)
```
export MYSQL_POD_NAME=`kubectl get pods --namespace=wifi-v5-api-public | grep mysql | cut -d' ' -f1`
kubectl port-forward $MYSQL_POD_NAME 3306:3306 --address 0.0.0.0 -n wifi-v5-api-public
```

Il y a aussi la possibilité de faire un "minikube service list" puis de récupérer l'IP:PORT du service exposé pour s'y connecter.
Autre solution, ajouter un nodeport au service.

## Tips kubectl divers

K9s: https://github.com/derailed/k9s
Auto-complétion: https://kubernetes.io/fr/docs/reference/kubectl/cheatsheet/
Plugin kubectl: https://github.com/kubernetes-sigs/krew/
Switch entre cluster et namespace facilement: https://github.com/ahmetb/kubectx
CheatSheet: https://linuxacademy.com/site-content/uploads/2019/04/Kubernetes-Cheat-Sheet_07182019.pdf
## Cheatsheet (à centraliser)

Exemple de commande kubectl utilisées pour cette application, avec donc le namespace "public-access-api":

```
kubectl get pods -n public-access-api
export PHP_POD_NAME=`kubectl get pods --namespace=public-access-api | grep php-fpm | cut -d' ' -f1`
kubectl logs $PHP_POD_NAME -n public-access-api
```
