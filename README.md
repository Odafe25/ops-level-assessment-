# hello-svc (prod + staging on AWS)

Deploy two EC2s (t2.small), each running the Go app (port 8080) via Docker Compose, fronted by Nginx (HTTPS 443, 80→443, /→/hello).

## Deploy
terraform init
terraform apply -auto-approve 

## Destroy
terraform destroy
