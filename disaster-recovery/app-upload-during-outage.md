DR Test: Mid-Upload Scale to Zero
Date: 2026-04-13
Result: PASS
_____________________________________________________________________

[Info]
Domain: Kubernetes / WordPress / MariaDB / NFS
Environment: DEV k8s-dev cluster | Proxmox
Triggered by: Need to verify data integrity when pods die during active user operations

_____________________________________________________________________

[Planned Scope]

Kill all WordPress pods while files are actively uploading. Check if
MariaDB ends up with orphaned records, if NFS has partial files, or
if anything gets corrupted. This simulates node failure / OOM kill /
power loss during real traffic.

Components expected to be affected: WordPress, MariaDB (InnoDB transactions), NFS storage

_____________________________________________________________________

[Pre-State]

Prerequisites fixed before running this test:
- PHP upload limits raised from 2MB to 100MB (TS-K8S-027)
- External nginx proxy_body_size set to 500m (TS-K8S-028)
Without these the uploads would've been blocked before even reaching WordPress.

DB baseline — 9 attachments already in wp_posts, latest ID=24:
```
+----+-------------------------------------------------------------+-------------+---------------------+
| ID | post_title                                                  | post_status | post_date           |
+----+-------------------------------------------------------------+-------------+---------------------+
| 24 | 1910013650_Festa Cloud-Based Controller_User Guide_REV1.3.0 | inherit     | 2026-04-13 16:23:25 |
| 23 | 672ef96e591a6cf83e75313e_672ef8dde0e15c7419c1ad5e_3         | inherit     | 2026-04-13 16:08:14 |
+----+-------------------------------------------------------------+-------------+---------------------+
(7 more rows, all inherit status, all clean)
```

_____________________________________________________________________

[Test 1.1 — Kill pods during active upload]

Action:
  Started 2 large PDF uploads simultaneously via WordPress admin.
  While both uploads in progress:
  ```
  kubectl scale deployment wordpress -n apps --replicas=0
  ```

What happened:
  - File 1 (ER605 UG): completed before SIGTERM hit — saved as ID 25
  - File 2: mid-upload when pods died — NOT in database

  DB after kill:
  ```
  | 25 | ER605(UN)_UG_USER_GUIDE | inherit | 2026-04-13 18:08:34 |  <- new, clean
  | 24 | 1910013650_Festa...     | inherit | 2026-04-13 16:23:25 |  <- unchanged
  ```

  Checked for orphaned/corrupted records:
  ```sql
  SELECT ID, post_title, post_status FROM wp_posts
  WHERE post_status NOT IN ('publish','inherit','draft','auto-draft');
  -- Empty set (0.000 sec)
  ```
  Zero garbage. InnoDB rolled back the incomplete transaction cleanly.

Cascade:
  Pod killed mid-PHP-execution → InnoDB transaction never committed →
  INSERT rolled back automatically → no orphaned DB record

What this tells me:
  The upload only lives on the pod that ingress routed the request to.
  That pod receives the file into /tmp (container-local), moves it to
  NFS (/wp-content/uploads/), then INSERTs into MariaDB and COMMITs.
  The other 2 WordPress pods know nothing about this upload.

  If the pod dies before COMMIT — InnoDB rolls back the INSERT, no
  orphaned DB record. If it dies before the NFS move — temp file was
  in container /tmp, gone with the pod. The only gap: pod dies after
  writing to NFS but before COMMIT — file sits on NFS with no matching
  DB record (orphan file, not a data integrity issue).

_____________________________________________________________________

[Test 1.2 — Kill MariaDB during active upload]

Date: 2026-04-22

Why this test: Test 1.1 killed the pod (PHP process dies). This time
  I wanted to see what happens when the DB goes down but the pod stays
  up — does the file land on NFS with no DB record (orphan)?

Action:
  Identified which pod I was on via ingress logs:
  ```
  "POST /wp-admin/upload.php" → upstream: 10.244.62.25:80
  ```
  Pod: wordpress-6d4f6bbd46-ghspb on worker1.

  Started uploading a 90mb mp4 via WordPress admin.
  While upload in progress:
  ```
  kubectl scale statefulset mariadb -n database --replicas=0
  ```

What happened:
  - Browser: "An error occurred in the upload. Please try again later."
  - NFS: no new file appeared (checked ls -lt on uploads/2026/04/)
  - DB: no new record after recovery (last ID before test unchanged)

  Note on file buffer location: PHP's upload_tmp_dir is unset (confirmed
  via php -i), which defaults to /tmp. But watching /tmp/php* during a
  normal upload showed nothing. The file also doesn't appear on NFS until
  after the upload fully completes. So we know where the buffer is NOT
  (/tmp, NFS) but didn't trace the exact staging location — could be
  PHP-FPM memory, kernel pipe buffer, or a different tmpfs path.
  Doesn't matter for the DR finding — wherever it is, it's gone when the
  request fails.

Cascade:
  DB scaled to 0 → WordPress tried to establish DB connection at the
  very start of request processing (class-wpdb.php line 1994,
  mysqli_real_connect → "Connection refused") → PHP never reached
  upload handling → no file buffered, no NFS write, no INSERT

  Evidence from pod logs:
  ```
  [Wed Apr 22 22:53:02] PHP Warning: mysqli_real_connect(): (HY000/2002):
    Connection refused in /var/www/html/wp-includes/class-wpdb.php on line 1994,
    referer: http://wordpress-dev.lab.local/wp-admin/upload.php
  ```

What this tells me:
  WordPress requires a DB connection before it processes anything — not
  just auth, but the raw mysqli connection in wpdb. No DB = no request
  processing at all. The upload never even starts. This means DB failure
  during upload = clean rejection at the gate. No orphan files, no partial
  state. Different from Test 1.1 where InnoDB rollback was the safety
  net — here the request never gets far enough to need a rollback.

Recovery:
  ```
  kubectl scale statefulset mariadb -n database --replicas=1
  ```
  MariaDB back in ~9s, WordPress immediately functional. Uploaded a file
  successfully after recovery to confirm.

_____________________________________________________________________

[Findings]

1. InnoDB ACID guarantees work under pod kill (Test 1.1). Transaction
   either fully commits or fully rolls back. No partial state.

2. DB failure during upload is even cleaner (Test 1.2). WordPress
   validates auth against MariaDB before accepting the file. DB down =
   request rejected immediately. File never buffers, never reaches NFS.

3. Two different safety mechanisms for two different failure modes:
   - Pod dies → InnoDB rollback (data layer safety)
   - DB dies → early auth rejection (application layer safety)
   Both result in zero orphans, but for different reasons.

4. File buffer location during upload is unknown. Not in /tmp, not on
   NFS until upload completes. Didn't trace further — irrelevant to
   the DR outcome but worth noting as an open question.

_____________________________________________________________________

[References]

- TS-K8S-027 — WordPress PHP upload limits fix
- TS-K8S-028 — External nginx proxy 413 error fix
- TS-K8S-003 — NFS hard mount causing pod hangs
- TS-K8S-007 — InnoDB O_DIRECT NFS incompatibility
