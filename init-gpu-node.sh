#!/usr/bin/env bash
set -euo pipefail
### Missing YUM packages
## required for EFA installer to work 
yum -y --enablerepo=amzn2-core-debuginfo install rdma-core-debuginfo
## extra ones from Romulo's original script 
yum install -y libaio-devel python3-debug

export GDRCOPY_VERSION=v2.4.1
export EFA_INSTALLER_VERSION=1.37.0
export AWS_OFI_NCCL_VERSION=1.12.1-aws
export NCCL_VERSION=v2.23.4-1
if [ -z "${LD_LIBRARY_PATH+x}" ]; then
	    export LD_LIBRARY_PATH=""
fi
export LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:/usr/local/lib:$LD_LIBRARY_PATH
export PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

#################################################
## Install pynvml
# curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
# python3 /tmp/get-pip.py 
pip3 install pynvml

#################################################
## Install NVIDIA GDRCopy
##
## NOTE: if `nccl-tests` or `/opt/gdrcopy/bin/sanity -v` crashes with incompatible version, ensure
## that the cuda-compat-xx-x package is the latest.
rm -rf /opt/gdrcopy
git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy
cd /tmp/gdrcopy
make prefix=/opt/gdrcopy install
rm -rf /tmp/gdrcopy

export LD_LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat:$LD_LIBRARY_PATH
if [ -z "${LIBRARY_PATH+x}" ]; then
	            export LIBRARY_PATH=""
fi

export LIBRARY_PATH=/opt/gdrcopy/lib:/usr/local/cuda/compat/:$LIBRARY_PATH
if [ -z "${CPATH+x}" ]; then
	                    export CPATH=""
fi

export CPATH=/opt/gdrcopy/include:$CPATH
export PATH=/opt/gdrcopy/bin:$PATH

#################################################
## Install EFA installer
cd /tmp
curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz
tar -xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz
cd aws-efa-installer
./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify
rm -rf /tmp/aws-efa-installer

###################################################
## Install NCCL
cd /tmp
rm -rf /opt/nccl
git clone -b ${NCCL_VERSION} https://github.com/NVIDIA/nccl.git /opt/nccl
cd /opt/nccl
## this was changed based on the p4de OnNodeConfiguration configuration script from this tutorial https://catalog.workshops.aws/ml-on-aws-parallelcluster/en-US
make -j $(nproc) src.build CUDA_HOME=/usr/local/cuda NVCC_GENCODE="-gencode=arch=compute_70,code=sm_70 -gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_90,code=sm_90"

###################################################
## Install AWS-OFI-NCCL plugin
#Switch from sh to bash to allow parameter expansion
cd /tmp
curl -OL https://github.com/aws/aws-ofi-nccl/releases/download/v${AWS_OFI_NCCL_VERSION}/aws-ofi-nccl-${AWS_OFI_NCCL_VERSION}.tar.gz
tar -xf aws-ofi-nccl-${AWS_OFI_NCCL_VERSION}.tar.gz
cd aws-ofi-nccl-${AWS_OFI_NCCL_VERSION}
./configure --prefix=/opt/aws-ofi-nccl/install \
        --with-mpi=/opt/amazon/openmpi \
        --with-libfabric=/opt/amazon/efa \
        --with-cuda=/usr/local/cuda \
        --enable-platform-aws
make -j $(nproc)
make install

## Set Open MPI variables to exclude network interface and conduit.
export OMPI_MCA_pml=^cm,ucx
export OMPI_MCA_btl=tcp,self
export OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent
export OPAL_PREFIX=/opt/amazon/openmpi
export NCCL_SOCKET_IFNAME=^docker,lo,veth_def_agent,eth

## Turn off PMIx Error https://github.com/open-mpi/ompi/issues/7516
export PMIX_MCA_gds=hash

## Set LD_PRELOAD for NCCL library
export LD_PRELOAD=/opt/nccl/build/lib/libnccl.so

echo "__DONE__"

