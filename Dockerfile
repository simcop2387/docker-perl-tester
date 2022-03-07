ARG BASE
FROM ${BASE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY cpanfile /tmp/


RUN apt-get update && \
        apt-get dist-upgrade -y && \
        apt-get -y --no-install-recommends install aspell aspell-en libquadmath0 libssl-dev build-essential zlib1g-dev git ca-certificates pkg-config && \
        apt-get -y build-dep libnet-ssleay-perl

RUN perl -V

RUN cpanm --self-upgrade || \
    ( echo "# Installing cpanminus:"; curl -sL https://cpanmin.us/ | perl - App::cpanminus )

RUN cpanm -nv App::cpm Carton::Snapshot Net::SSLeay LWP::UserAgent LWP::Protocol::https

RUN cpm install -g --show-build-log-on-failure --cpanfile /tmp/cpanfile

RUN cpan-outdated --exclude-core -p | xargs -n1 cpanm

WORKDIR /tmp/
RUN git clone https://github.com/perl-actions/ci-perl-tester-helpers.git --depth 1 && \
    cp ci-perl-tester-helpers/bin/* /usr/local/bin/ && \
    rm -rf ci-perl-tester-helpers

CMD ["/bin/bash"]
