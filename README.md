## Clone the Repo
```sh
git clone https://github.com/Pinchez25/rabbitmq_ui.git
cd rabbitmq_ui
```
### Create a file .env.production with contents
```env
# RabbitMQ Configuration
NEXT_PUBLIC_RABBITMQ_HOST=localhost
NEXT_PUBLIC_RABBITMQ_PORT=15672
NEXT_PUBLIC_RABBITMQ_VHOST=/

# RabbitMQ Credentials (not public)
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest

# Next.js Configuration
NEXT_PUBLIC_API_URL=http://localhost:3000
```
### Add rabbitmq.localhost to hosts file
```sh
sudo vim /etc/hosts
# add at the end
127.0.0.1   rabbitmq.localhost
```
### Run the scripts
```sh
chmod +x ./setup.sh
./setup.sh
```
```sh
chmod +x ./deploy.sh
./deploy.sh 
```
Access the application in your browser:
[Open RabbitMQ App](http://rabbitmq.localhost/)

