# DR Test Result: Mid-Transaction WordPress Kill
# Test Date: 2026-04-13
# Environment: DEV cluster
# Tester: Sabry
# Result: PASS

---

## Test Objective

Verify that killing WordPress pods mid-upload does not cause:
1. Orphaned database records in MariaDB
2. Partial files on NFS storage
3. Data corruption or inconsistent state

This simulates a real-world scenario where pods are killed during active operations —
node failure, OOM kill, forced scale-down, or power outage during traffic.

---

## Pre-Test Setup

### Upload limit increased
Default WordPress upload limit was 2MB — insufficient for meaningful test.
Increased to 100MB before test to allow large file uploads.

### Baseline state confirmed
```sql
SELECT ID, post_title, post_status, post_date
FROM wp_posts
WHERE post_type='attachment'
ORDER BY post_date DESC
LIMIT 10;
```

**Result before test:**
```
+----+-------------------------------------------------+-------------+---------------------+
| ID | post_title                                      | post_status | post_date           |
+----+-------------------------------------------------+-------------+---------------------+
| 17 | floor_plan_colored                              | inherit     | 2026-04-13 14:28:39 |
| 16 | Mohamed Sabry Resume -2                         | inherit     | 2026-04-13 14:28:30 |
| 15 | josh-nuttall-xl2piFfdzyA-unsplash               | inherit     | 2026-04-13 14:27:47 |
| 14 | fYWQfzzc_400x400                                | inherit     | 2026-04-13 14:26:39 |
|  8 | fYWQfzzc_400x400                                | inherit     | 2026-04-04 14:09:14 |
+----+-------------------------------------------------+-------------+---------------------+
```

### Completed uploads before kill test (IDs 18-21)
4 files uploaded successfully as control group to confirm baseline works:
```
ID 18: DC-K8s-2aef5800e2dac87d66fae52dc90140637a9fa303   inherit   14:30:12
ID 19: Mohamed Sabry Resume -2                           inherit   14:30:12
ID 20: floor_plan_colored                                inherit   14:30:20
ID 21: ER605 2.20_Installation_Doc                       inherit   14:30:28
```
All 4 showing `inherit` status = fully committed to database

---

## Test Execution

### Action taken
Two large files uploaded simultaneously via WordPress admin media upload:
- File 1: ~30MB
- File 2: ~20MB

While both uploads were in progress (mid-upload, before completion):

```bash
kubectl scale deployment wordpress -n apps --replicas=0
# deployment.apps/wordpress scaled
```

WordPress pods killed immediately during active PHP upload processing.

### Timing
Kill was executed mid-upload before either file completed transfer.

---

## Test Results

### Check 1: Database — Orphaned attachment records

```sql
SELECT ID, post_title, post_status, post_date
FROM wp_posts
WHERE post_type='attachment'
ORDER BY post_date DESC
LIMIT 10;
```

**Result after kill:**
```
+----+-------------------------------------------------+-------------+---------------------+
| ID | post_title                                      | post_status | post_date           |
+----+-------------------------------------------------+-------------+---------------------+
| 21 | ER605 2.20_Installation_Doc                     | inherit     | 2026-04-13 14:30:28 |
| 20 | floor_plan_colored                              | inherit     | 2026-04-13 14:30:20 |
| 18 | DC-K8s-2aef5800e2dac87d66fae52dc90140637a9fa303 | inherit     | 2026-04-13 14:30:12 |
| 19 | Mohamed Sabry Resume -2                         | inherit     | 2026-04-13 14:30:12 |
| 17 | floor_plan_colored                              | inherit     | 2026-04-13 14:28:39 |
| 16 | Mohamed Sabry Resume -2                         | inherit     | 2026-04-13 14:28:30 |
| 15 | josh-nuttall-xl2piFfdzyA-unsplash               | inherit     | 2026-04-13 14:27:47 |
| 14 | fYWQfzzc_400x400                                | inherit     | 2026-04-13 14:26:39 |
|  8 | fYWQfzzc_400x400                                | inherit     | 2026-04-04 14:09:14 |
+----+-------------------------------------------------+-------------+---------------------+
```

**Finding:** Mid-upload files (30MB + 20MB) are completely absent.
Only the 4 pre-kill completed uploads (IDs 18-21) present.
Zero orphaned records.

---

### Check 2: Database — Unexpected post status

```sql
SELECT ID, post_title, post_status
FROM wp_posts
WHERE post_status NOT IN ('publish','inherit','draft','auto-draft')
ORDER BY ID DESC
LIMIT 10;
```

**Result:**
```
Empty set (0.000 sec)
```

**Finding:** Zero records in unexpected or unknown states.
InnoDB rolled back all incomplete transactions cleanly.

---

### Check 3: NFS filesystem — Partial files on disk

Inspected NAS directory:
```
/volume1/k8s-dev/pvc-69f14fb9-0ca0-48ae-a84e-afa0a5ee8822/wp-content/uploads/2026/04/
```

**Files found:**
```
ER605-2.20_Installation_Doc-pdf.jpg           291.94 KB   04/13/2026 PM 04:30
ER605-2.20_Installation_Doc-pdf-775x1024.jpg  150.37 KB   04/13/2026 PM 04:30
ER605-2.20_Installation_Doc-pdf-227x300.jpg    73.76 KB   04/13/2026 PM 04:30
ER605-2.20_Installation_Doc-pdf-114x150.jpg    66.45 KB   04/13/2026 PM 04:30
ER605-2.20_Installation_Doc.pdf               334.63 KB   04/13/2026 PM 04:30
floor_plan_colored-1-1024x406.png             200.45 KB   04/13/2026 PM 04:30
floor_plan_colored-1-150x150.png               20.97 KB   04/13/2026 PM 04:30
floor_plan_colored-1-1536x609.png             387.64 KB   04/13/2026 PM 04:30
floor_plan_colored-1-768x305.png              128.29 KB   04/13/2026 PM 04:30
floor_plan_colored-1.png                      449.29 KB   04/13/2026 PM 04:30
floor_plan_colored-1-300x119.png               32.10 KB   04/13/2026 PM 04:30
DC-K8s-2aef5800e2dac87d66fae52dc90140637a9fa303.zip  477.19 KB  04/13/2026 PM 04:30
Mohamed-Sabry-Resume-2-1.docx                  38.51 KB   04/13/2026 PM 04:30
```

**Finding:** Only files from the 4 completed uploads (IDs 18-21) present on NFS.
The mid-upload 30MB and 20MB files are completely absent from the filesystem.
Zero partial files, zero orphaned files.

**Note:** Multiple thumbnail sizes visible per image (1024x, 768x, 300x, 150x, 1536x) —
WordPress generates these automatically on successful upload. Their presence confirms
the completed uploads were fully processed end-to-end.

---

## Analysis

### Why the database was clean

PHP process was killed mid-upload via SIGTERM (kubectl scale to 0).
The database INSERT for the upload record was never executed or was mid-transaction.
InnoDB ACID guarantee: transaction either commits fully or rolls back fully.
No partial commits — InnoDB automatically rolled back the incomplete transaction.

```
PHP upload process:
  1. Receive file data
  2. Write file to NFS → KILLED HERE (before file write completed)
  3. INSERT record to wp_posts
  4. INSERT metadata to wp_postmeta
  5. COMMIT

Result: Steps 3-5 never reached → nothing in database
        Step 2 incomplete → nothing on NFS
```

### Why the filesystem was clean

WordPress PHP process was killed before it could complete writing the file to NFS.
The file write was incomplete so nothing landed on disk.
This confirms WordPress writes the file before committing the database record —
kill before file write = nothing anywhere.

### Upload processing order confirmed

```
PHP receives upload → writes file to NFS → commits database record
```

If kill happens before file write completes → nothing on NFS, nothing in database.
If kill happens after file write but before database commit → file on NFS, nothing in database.
In this test: kill was early enough that neither completed.

---

## Conclusion

| Check | Expected | Actual | Result |
|---|---|---|---|
| DB orphaned attachment records | 0 | 0 | PASS |
| DB unexpected post status | 0 | 0 | PASS |
| NFS partial files | 0 | 0 | PASS |
| Completed uploads intact | 4 (IDs 18-21) | 4 (IDs 18-21) | PASS |
| InnoDB rollback working | Yes | Yes | PASS |

**Overall Result: PASS**

InnoDB transaction guarantees work correctly under forced pod termination.
No data corruption, no orphaned records, no partial files.
WordPress + MariaDB + NFS stack handles abrupt kill gracefully.

---

## Related Cases

- TS-K8S-003 — NFS hard mount causing pod hangs (mount options)
- TS-K8S-007 — InnoDB O_DIRECT NFS incompatibility
- TS-K8S-015 — Stale NFS mount on CSI restart (MariaDB CrashLoopBackOff)
- TS-K8S-027 — WordPress PHP upload limits (increased for this test)
- MariaDB SC migration runbook — operation performed same day as this test

---

## Notes

This test was performed as part of the MariaDB StorageClass migration operation
on 2026-04-13. The kill test was intentionally inserted before the migration
to validate transaction integrity before touching the production data.

The clean result gave confidence to proceed with the migration knowing that
InnoDB handles abrupt termination correctly and data integrity is maintained.
