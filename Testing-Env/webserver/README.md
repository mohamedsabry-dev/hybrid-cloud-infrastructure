the The project will live based on Test2 VM in prod server ( Scoped 12-13 July)
1 varnish >> 1 nginx >> 2 Apache >> 1 PostgresSQL 

Phase 1 is to run it end to end 

Phase 2 is to containerize it : " This will run into Node Test1 Docker based (Scoped 12-13 July)
- 4 Images [varnish,nginx,apache,postgres]
- manual build local 
- 5 containers build with docker-compose 

Phase 3 is to Pipe it [ 1 GH Action workflow to build 4 public images, get db secret from gh secrret] (Later)

Phase 4 is to deployment as Pods (Later)