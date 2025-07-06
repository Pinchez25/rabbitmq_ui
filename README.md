## Clone the Repo
```sh
git clone https://github.com/Pinchez25/rabbitmq_ui.git
cd rabbitmq_ui
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

