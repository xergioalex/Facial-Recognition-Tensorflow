FROM python:3.5

WORKDIR /app

RUN git clone https://github.com/xergioalex/facenet.git
RUN cd /app/facenet && pip3 install -r requirements.txt
RUN cd /app && wget https://raw.githubusercontent.com/xergioalex/Facial-Recognition-Tensorflow/master/requirements.txt \
	&& ls -la /app \
	&& pip3 install -r requirements.txt