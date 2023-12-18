sudo mkdir /etc/web
sudo chmod 666 /etc/web
aws s3 cp s3://${bucket_name}/tls.cert /etc/web
aws s3 cp s3://${bucket_name}/tls.key /etc/web
aws s3 cp s3://${bucket_name}/zarf-config.yaml /etc/web
