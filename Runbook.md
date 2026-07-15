## 📋 Runbook d'Exploitation (Section B)

### 🔄 1. Procédures de Redémarrage d'Urgence (Restart)

Si un composant applicatif présente une défaillance ou si vous devez recharger sa configuration sans interruption de service (Rolling Update) :

#### Redémarrer un composant Stateless (Frontend, Catalog API, Orders API)

L'orchestrateur va créer de nouveaux pods sains en arrière-plan puis détruire proprement les anciens sans aucune coupure réseau :

```bash
# Exemple pour le Frontend
kubectl rollout restart deployment green-trade-frontend -n green-trade

# Exemple pour l'API Catalog
kubectl rollout restart deployment green-trade-catalog-api -n green-trade

# Exemple pour l'API Orders
kubectl rollout restart deployment green-trade-orders-api -n green-trade
```

#### Redémarrer le composant Stateful (MongoDB)
La base de données étant un StatefulSet, elle est liée à son volume persistant. Pour la redémarrer proprement sans perte de données (le disque persistant sera réattaché automatiquement) :

```bash
kubectl delete pod green-trade-mongo-0 -n green-trade
```

### 💾 2. Sauvegarde et Restauration de la Base de Données (MongoDB)

#### Procédure de Sauvegarde (Backup)
La sauvegarde génère une archive compressée autonome de l'ensemble de la base de données greentrade.

```bash
# 1. Générer le dump directement à l'intérieur du conteneur de base de données
kubectl exec -it green-trade-mongo-0 -n green-trade -- mongodump --db=greentrade --archive=/tmp/greentrade_backup.archive --gzip

# 2. Rapatrier l'archive de sauvegarde sur votre Mac local
kubectl cp green-trade/green-trade-mongo-0:/tmp/greentrade_backup.archive ./greentrade_backup.archive

# 3. Nettoyer le fichier temporaire dans le pod
kubectl exec -it green-trade-mongo-0 -n green-trade -- rm /tmp/greentrade_backup.archive

echo "Sauvegarde terminée avec succès : ./greentrade_backup.archive"
```

#### Procédure de Restauration (Restore)
Cette procédure écrase les données actuelles de la base pour restaurer l'état exact contenu dans l'archive.

```bash
# 1. Envoyer le fichier de sauvegarde local dans le pod MongoDB
kubectl cp ./greentrade_backup.archive green-trade/green-trade-mongo-0:/tmp/greentrade_backup.archive

# 2. Exécuter la restauration avec suppression des collections existantes (option --drop)
kubectl exec -it green-trade-mongo-0 -n green-trade -- mongorestore --archive=/tmp/greentrade_backup.archive --gzip --drop

# 3. Nettoyer le fichier temporaire dans le pod
kubectl exec -it green-trade-mongo-0 -n green-trade -- rm /tmp/greentrade_backup.archive

echo "Restauration terminée avec succès !"
```