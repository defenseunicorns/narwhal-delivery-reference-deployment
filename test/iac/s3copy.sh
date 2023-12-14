sudo aws s3 cp s3://${bucket_name}/tls.cert /etc/web
suco aws s3 cp s3://${bucket_name}/tls.key /etc/web
sudo aws s3 cp s3://${bucket_name}/zarf-config.yaml /etc/web