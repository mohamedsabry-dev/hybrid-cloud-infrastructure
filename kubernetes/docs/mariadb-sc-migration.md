PRE-OPERATION
─────────────
1. Backup old NAS directory (safety net for human error)
   cp -r /volume1/k8s-prod/pvc-ffbc1708-.../ /volume1/k8s-prod/mariadb-backup/

2. Suspend Flux apps Kustomization
   flux suspend kustomization apps

## Will upload 2 files , 1 wait to complete and 1 while complete will scale wordpress to 0 so we have left over transaction , so we do breif test for the operation while apply also 

CLEAN SHUTDOWN
──────────────
3. Scale WordPress to 0 (stop all incoming transactions)
   kubectl scale deployment wordpress -n apps --replicas=0
   kubectl get pods -n apps -w   # wait until all gone


# Check MariaDB for orphaned upload records
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p
    > use wordpress;
    > SELECT * FROM wp_posts WHERE post_status='inherit' ORDER BY post_date DESC LIMIT 5;
    > SELECT * FROM wp_postmeta WHERE meta_key='_wp_attached_file' ORDER BY meta_id DESC LIMIT 5;

4. Flush MariaDB and clean shutdown
   kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p
   > FLUSH TABLES WITH READ LOCK;
   > SHOW PROCESSLIST;   # confirm no active transactions
   > EXIT;

5. Scale MariaDB to 0 (clean InnoDB shutdown via SIGTERM)
   kubectl scale statefulset mariadb -n database --replicas=0
   kubectl get pods -n database -w   # wait until pod gone

6. Delete StatefulSet (required — volumeClaimTemplate is immutable)
   kubectl delete statefulset mariadb -n database

FLUX CREATES NEW SETUP
──────────────────────
7. Git — update statefulset.yaml:
         storageClassName: nfs-database
         replicas: 0
   Git — WordPress replicas stays at 3 (unchanged)
   push → flux resume kustomization apps

8. Flux reconciles:
   - creates new StatefulSet (replicas: 0)
   - creates new PVC on nfs-database StorageClass
   - CSI creates new empty NAS directory (pvc-<new-uuid>)
   - NO pod starts yet ✅
   - WordPress comes back up (replicas: 3 in Git) ✅

   Verify new PVC created:
   kubectl get pvc -n database -w
   # mariadb-data-mariadb-0   Bound   pvc-<new-uuid>   nfs-database

DATA MIGRATION
──────────────
9. Identify new NAS directory
   kubectl get pv <new-pv-name> -o yaml | grep subdir

10. Copy data from old NAS dir to new NAS dir
    cp -r /volume1/k8s-prod/pvc-ffbc1708-.../* \
          /volume1/k8s-prod/pvc-<new-uuid>/

11. Verify copy completed successfully
    ls -la /volume1/k8s-prod/pvc-<new-uuid>/
    # should see ibdata1, ib_logfile0, wordpress/, mysql/ etc

START MARIADB ON NEW PVC
────────────────────────
12. Git — update statefulset.yaml: replicas: 1
    push → Flux applies

13. Watch MariaDB start
    kubectl get pods -n database -w
    # mariadb-0   Init:0/1 → PodInitializing → Running 2/2 ✅

14. Verify data intact
    kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p
    > show databases;
    # wordpress present ✅
    > use wordpress; show tables;
    # all tables present ✅

15. Verify WordPress working
    curl https://wordpress-dev.lab.local
    # 200 OK ✅

CLEANUP
───────
16. Delete old Released PV
    kubectl delete pv pvc-ffbc1708-...

17. Delete old NAS directory
    rm -rf /volume1/k8s-prod/pvc-ffbc1708-.../

18. Delete backup when confident everything is good
    rm -rf /volume1/k8s-prod/mariadb-backup/