FROM python:3.5

# Install uWSGI
RUN pip3 install uwsgi

RUN mkdir -p /app

RUN cd /app && git clone https://github.com/xergioalex/facenet.git
RUN cd /app/facenet && pip3 install -r requirements.txt
RUN cd /app && wget https://raw.githubusercontent.com/xergioalex/Facial-Recognition-Tensorflow/master/requirements.txt \
	&& pip3 install -r requirements.txt


WORKDIR /app/Facial-Recognition-Tensorflow

COPY ./ ./

CMD /usr/local/bin/uwsgi --ini /app/uwsgi.ini