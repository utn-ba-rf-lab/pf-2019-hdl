FROM ubuntu:20.04

# https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
ENV TZ=America/Argentina/Buenos_Aires

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# UTN Ubuntu 20.04 repositories
COPY ./sources.20.04.list /etc/apt/sources.list

# dependencies for lattice toolchain
RUN apt-get update
RUN mkdir /build && apt-get update 
	#apt-get install -y aptitude
	
RUN apt-get install -y build-essential clang clang-format bison flex \
	libreadline-dev gawk tcl-dev libffi-dev git mercurial graphviz \
	xdot pkg-config python python3 libftdi-dev \
	qt5-default python3-dev libboost-all-dev cmake wget


ENV HTTP_PROXY="http://proxy.frba.utn.edu.ar:3128"
ENV HTTPS_PROXY="http://proxy.frba.utn.edu.ar:3128"

# lattice toolchain
RUN git clone https://github.com/cliffordwolf/icestorm.git /build/icestorm
RUN git clone https://github.com/YosysHQ/nextpnr.git /build/nextpnr
RUN git clone https://github.com/YosysHQ/arachne-pnr.git /build/arachne-pnr
RUN git clone https://github.com/YosysHQ/yosys.git /build/yosis

# more dependencies for lattice toolchain
RUN apt-get install -y libboost-dev libboost-filesystem-dev libboost-thread-dev libboost-program-options-dev libboost-python-dev libboost-dev libeigen3-dev qt5-default clang-format 

# build and install lattice toolchain
RUN cd /build/icestorm && make -j$(nproc) && make install
RUN cd /build/nextpnr && cmake -DARCH=ice40 . && make -j$(nproc) && make install
RUN cd /build/arachne-pnr && make -j$(nproc) && make install
RUN cd /build/yosis && make -j$(nproc) && make install
RUN rm -rf /build/

#Proxy Curl config
RUN echo "proxy=http://proxy.frba.utn.edu.ar:3128" >  ~/.curlrc

# install npm
ENV NODE_VERSION=16.13.0  
RUN apt install -y curl && \
 	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
ENV NVM_DIR=/root/.nvm 
RUN	. "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION} && \
	. "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION} && \
	. "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION} 
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
RUN npm install -g netlistsvg
RUN apt-get install -y vim
