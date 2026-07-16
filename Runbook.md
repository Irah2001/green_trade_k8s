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

### 🔄 3. Rollback et Récupération

#### Annuler un déploiement défaillant (Rollback de Deployment)

Si un nouveau déploiement introduit une régression ou instabilité, vous pouvez revenir à la version précédente sans perte de données :

```bash
# Consulter l'historique des déploiements
kubectl rollout history deployment green-trade-catalog-api -n green-trade

# Voir les détails d'une révision spécifique
kubectl rollout history deployment green-trade-catalog-api -n green-trade --revision=2

# Revenir à la révision précédente
kubectl rollout undo deployment green-trade-catalog-api -n green-trade

# Revenir à une révision spécifique
kubectl rollout undo deployment green-trade-catalog-api -n green-trade --to-revision=2

# Suivre la progression du rollback
kubectl rollout status deployment green-trade-catalog-api -n green-trade
```

La même procédure s'applique aux autres Deployments (Frontend, Orders API) en remplaçant le nom du Deployment.

#### Récupération après perte de NetworkPolicy

Si une `NetworkPolicy` a été accidentellement supprimée et que le cluster se trouve dans un état d'isolation excessive :

```bash
# Réappliquer les policies de sécurité
kubectl apply -f k8s/security/network-policy.yaml

# Vérifier que les policies sont réinstallées
kubectl get networkpolicy -n green-trade
```

#### Récupération après violation de PodSecurity

Si le label `pod-security.kubernetes.io/enforce` a été modifié accidentellement et que les pods ne peuvent plus être déployés :

```bash
# Restaurer les labels de sécurité au niveau du namespace
kubectl label namespace green-trade \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

#### Inspection de la configuration de sécurité actuelle

Pour diagnostiquer des problèmes de sécurité ou vérifier que le cluster respecte les standards :

```bash
# Vérifier le RBAC
kubectl get serviceaccount -n green-trade
kubectl get role -n green-trade
kubectl describe rolebinding green-trade-app -n green-trade

# Vérifier les NetworkPolicies
kubectl get networkpolicy -n green-trade
kubectl describe networkpolicy default-deny-all -n green-trade

# Vérifier le PodSecurity du namespace
kubectl get namespace green-trade -o jsonpath='{.metadata.labels}' | grep pod-security

# Vérifier le securityContext d'un pod
kubectl get pod <POD_NAME> -n green-trade -o jsonpath='{.spec.securityContext}'
```

