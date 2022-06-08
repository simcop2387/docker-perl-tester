ARG BASE
FROM ${BASE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY cpanfile /tmp/


RUN apt-get update && \
        apt-get dist-upgrade -y && \
        apt-get -y --no-install-recommends install aspell aspell-en libssl-dev build-essential zlib1g-dev git ca-certificates pkg-config && \
        (apt-get -y --no-install-recommends install libquadmath0 || echo no quadmath supported here) && \
        apt-get -y build-dep libnet-ssleay-perl && \
        apt-get clean && rm -fr /var/cache/apt/* /var/lib/apt/lists/* && rm -fr ./cpanm /root/.cpanm /usr/src/perl /usr/src/App-cpanminus-*


RUN perl -V

RUN ( cpanm --self-upgrade || \
    ( echo "# Installing cpanminus:"; curl -sL https://cpanmin.us/ | perl - App::cpanminus )) && cpanm -nv App::cpm Carton::Snapshot Net::SSLeay LWP::UserAgent LWP::Protocol::https && rm -rf /root/.cpanm

RUN cpm install -g --show-build-log-on-failure --cpanfile /tmp/cpanfile && rm -rf /root/.perl-cpm

RUN cpan-outdated --exclude-core -p | xargs -n1 cpanm && rm -rf /root/.cpanm

WORKDIR /tmp/
RUN git clone https://github.com/perl-actions/ci-perl-tester-helpers.git --depth 1 && \
    cp ci-perl-tester-helpers/bin/* /usr/local/bin/ && \
    rm -rf ci-perl-tester-helpers

RUN perl -i -E 's|#!/usr/bin/perl|#!/usr/local/bin/perl|' /usr/local/bin/cpanm && /usr/local/bin/cpanm --version

CMD ["/bin/bash"]
