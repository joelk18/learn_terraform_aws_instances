## Terraform to deploy instance on aws for ETL job

This project aims to extract data from RDS database with **aws glue**, apply transformation to **STAR** by using pyspark, then load it on S3.

```
learn-terraform-aws-instance/
├── README.md
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── glue/
│       └── etl_job.py
```
