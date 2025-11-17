ARG wgutils_url="https://github.com/amnezia-vpn/amneziawg-tools.git" build_dir="/build"

FROM alpine:edge as builder

ARG wgutils_url build_dir

RUN apk update && apk upgrade && apk add --no-cache build-base linux-headers git && mkdir "${build_dir}" && git clone "${wgutils_url}" "${build_dir}"

WORKDIR "${build_dir}"/src

RUN make clean && make && make install DESTDIR="${build_dir}"/artifacts && cp "${build_dir}"/src/wg-quick/linux.bash "${build_dir}"/artifacts/usr/bin/awg-quick && sed -i '/^[[:space:]]*auto_su()/! s/\<auto_su\>/#auto_su/' "${build_dir}"/artifacts/usr/bin/awg-quick

# --------------------------------------------------------------

FROM alpine:edge

ARG rootless_username=awg rootless_uid=65500
ARG wgutils_url build_dir

ENV WG_APP_DIR="/opt/amneziawg/scripts" WG_TPL_DIR="/etc/amnezia/templates"
ENV WG_SERVER_CFG_DIR="/etc/amnezia/amneziawg" WG_SERVER_CFG_FILE=awg0.conf WG_INTERNAL_SUBNET="10.12.12.0/24" DNS_BUILTIN="false"
ENV PATH="${WG_APP_DIR}:${PATH}"

#COPY --chmod=0750 --chown="${rootless_username}":"${rootless_username}" files/* /usr/local/bin/
COPY --chmod=0550 --from=builder "${build_dir}"/artifacts/usr/bin/* ${WG_APP_DIR}/
#COPY --chmod=0550 --from=builder "${build_dir}"/src/wg-quick/linux.bash /usr/local/bin/awg-quick

RUN apk update && apk upgrade \
 && apk add --no-cache bash coredns coreutils iptables tzdata gettext libqrencode-tools jq \
 && apk cache clean && rm -rf /var/cache/apk/* \
 && adduser "${rootless_username}" -D -u ${rootless_uid} -s /bin/false \
 && mkdir -p -m 755 "${WG_TPL_DIR}" && mkdir -p -m 750 "${WG_SERVER_CFG_DIR}"/peers "${WG_SERVER_CFG_DIR}"/backup "${WG_APP_DIR}" \
 && chown "${rootless_username}":"${rootless_username}" -R /etc/amnezia/ "${WG_APP_DIR}" \
 && mkdir -p -m 555 /artifacts/share/man/man8/

COPY --chmod=0444 files/templates/* ${WG_TPL_DIR}
COPY --chmod=0550 --chown="${rootless_username}":"${rootless_username}" files/awg_scripts/* "${WG_APP_DIR}/"
COPY --chmod=0555 --from=builder "${build_dir}"/artifacts/usr/share/man/man8/awg.8 /artifacts/share/man/man8/
COPY --chmod=0640 --chown="${rootless_username}":"${rootless_username}" files/Corefile /etc/coredns/Corefile

#left for testing
#COPY --chmod=0750 --chown="${rootless_username}":"${rootless_username}" files/* /usr/local/bin/
#RUN setcap cap_net_admin=eip /usr/local/bin/awg && setcap cap_net_admin=eip $(readlink -f /usr/sbin/iptables)

WORKDIR ${WG_SERVER_CFG_DIR}
USER "${rootless_username}"

EXPOSE 51820/udp
COPY --chmod=554 --chown="${rootless_username}":"${rootless_username}" entrypoint.sh /
CMD ["/bin/sh","-c","/entrypoint.sh"]
