FROM debian:11-slim as build

# libgssapi-krb5-2 \
# liblttng-ust0 \
# libunwind8 \
# libuuid1 \
# zlib1g \
# curl \
# libcomerr2 \
# libidn2-0 \
# libk5crypto3 \
# libkrb5-3 \
# libldap-2.4-2 \
# libldap-common \
# libsasl2-2 \
# libsasl2-modules-db \
# libnghttp2-14 \
# libpsl5 \
# librtmp1 \
# libssh2-1 \
# libkeyutils1 \
# libkrb5support0 \
# libgnutls30 \
# libgmp10 \
# libhogweed4 \
# libidn11 \
# libnettle6 \
# libp11-kit0 \
# libffi6 \
# libtasn1-6 \
# libdb5.3 \
# libgcrypt20 \
# libgpg-error0 \
# libacl1 \
# libattr1 \
# libselinux1 \
# libpcre3 \
# libbz2-1.0 \
# liblzma5 \
# libcurl4 \
# libssl1.1 \
# libicu63 \
# libunistring2 \

# microsoft docs to debian dependencies
# https://docs.microsoft.com/en-us/dotnet/core/install/linux-debian#dependencies
# docs for self contained dependencies
# https://github.com/dotnet/core/blob/main/Documentation/self-contained-linux-apps.md
# distroless PR to drop dotnet (there are also important infos)
# https://github.com/GoogleContainerTools/distroless/pull/711/files

# more infos to how extract for the CVE scan relevant parts from deb packages
# see https://github.com/GoogleContainerTools/distroless/issues/863
RUN cd /tmp && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        # install only deps
        curl \
        ca-certificates \
        openssl \
        && \
    apt-get download \
        # ca-certificates \
        \
        # .NET Core dependencies
        libc6 \
        libgcc-s1 \
        libgssapi-krb5-2 \
        libicu67 \
        libssl1.1 \
        libstdc++6 \
        zlib1g \
        && \
    mkdir -p /dpkg/var/lib/dpkg/status.d/ && \
    for deb in *.deb; do \
        package_name=$(dpkg-deb -I ${deb} | awk '/^ Package: .*$/ {print $2}'); \ 
        echo "Process: ${package_name}"; \
        dpkg --ctrl-tarfile $deb | tar -Oxf - ./control > /dpkg/var/lib/dpkg/status.d/${package_name}; \
        dpkg --extract $deb /dpkg || exit 10; \
    done

# remove not needed files extracted from deb packages like man pages and docs etc.
RUN find /dpkg/ -type d -empty -delete && \
    rm -r /dpkg/usr/share/doc/

# Retrieve .NET runtime
RUN dotnet_version='6.0.15' \
    && dotnet_sha512='681928ab5050da89302518445f4e7e00738530b3941434fad363724ad5b1f9bcdc52717332613d2e33733ebf835eb550628e87cebba1a12ffb4f881c8e767749' \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz \
    && echo "$dotnet_sha512  dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /dotnet \
    && tar -ozxf dotnet.tar.gz -C /dotnet \
    && rm dotnet.tar.gz

# Retrieve ASP.NET Core
RUN aspnet_version='6.0.15' \
    && aspnetcore_sha512='db41bbd6ffb061402acee12f498f41fe5987d355c9004091ff63010303cc9ea969ab233986dc11556bc6def5194883f50fdf216e1c50b26bb60cacd4f2ecd98a' \
    && curl -SL --output aspnetcore.tar.gz https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/$aspnet_version/aspnetcore-runtime-$aspnet_version-linux-x64.tar.gz \
    && echo "$aspnetcore_sha512  aspnetcore.tar.gz" | sha512sum -c - \
    && mkdir -p /aspnet \
    && tar -ozxf aspnetcore.tar.gz -C /aspnet \
    && rm aspnetcore.tar.gz

FROM gcr.io/distroless/cc-debian11 as runtime-deps
COPY --from=build ["/dpkg/", "/"]

FROM runtime-deps as runtime
ENV \
    # .NET runtime version
    DOTNET_VERSION=6.0.15 \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Set the default console formatter to JSON
    Logging__Console__FormatterName=Json
COPY --from=build ["/dotnet", "/usr/share/dotnet"]

FROM runtime as aspnet
ENV \
    # Configure web servers to bind to port 8080 (to be able to run as nonroot)
    ASPNETCORE_URLS=http://+:8080 \
    # ASP.NET Core version
    ASPNET_VERSION=6.0.15
COPY --from=build ["/aspnet", "/usr/share/dotnet"]
