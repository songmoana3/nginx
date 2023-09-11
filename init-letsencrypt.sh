#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then # docker-compose 실행
  echo 'Error: docker-compose is not installed.' >&2 # 에러 반환
  exit 1
fi

domains=(songmoana.duckdns.org)
rsa_key_size=4096
data_path="./data/certbot"
email="songmoana3@gmail.com"
staging=0 # 테스트를 위한 스테이징 모드 사용 여부 0: 미사용 1: 사용

if [ -d "$data_path" ]; then
  read -p "지정된 데이터 경로가 이미 존재 ... $domains. 기존 인증서를 대체할 것인가? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then # 기존 인증서 유지하고 싶다고 하면 (N) 일경우 스크립트 종료!
    exit
  fi
fi


if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then # 추천 TSL 매개변수 파일들이 존재하지 않는 경우, 다운로드
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Fake 인증서 발급받는중 . . .  $domains ..."
path="/etc/letsencrypt/live/$domains" # 인증서와 관련된 경로를 정의한다.
mkdir -p "$data_path/conf/live/$domains"
# echo "$data_path/conf/live/$domains"
docker-compose run --rm --entrypoint "\ 
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot # 인증서를 생성하기 위해 OpenSSL 명령어를 사용하여 self-signed(자체서명) 인증서를 생성한다.
# --rm : 컨테이너가 종료되면 해당 컨테이너를 자동으로 삭제하는 옵션
# --entrypoint : 컨테이너가 시작될 때 지정된 명령어를 대체하는데 사용 -> Certbot 의 인증서 생성 명령어를 직접 제공
# -days : 인증서의 유효 기간을 n일로 설정
# -keyout : 개인 키를 파일에 저장
# -out : 전체 인증서 체인을 파일에 저장
# -subj : 인증서가 localhost 도메인에 사용되도록 설정
echo


echo "nginx 실행중..."
docker-compose up --force-recreate -d reverse_proxy # NGINX 서버 시작
echo

echo "### Fake 인증서 삭제하는중 . . . $domains ..."
docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot # 이전에 생성한 Fake 인증서를 삭제
echo


echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args="" # 인증서를 요청할 도메인들을 모으기 위한 빈 문자열을 초기화한다.
for domain in "${domains[@]}"; do # 도메인을 순회하며 각 도메인을 -d 옵션과 함께 domain_args 에 추가한다.
  domain_args="$domain_args -d $domain"
done

# 이메일 주소에 따라 적절한 Certbot 옵션을 선택한다. 이메일이 비어있을 경우, 스테이징 모드를 사용하기 위한 옵션을 설정한다.
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# 값이 0 이 아니면 스테이징 모드를 사용하기 위한 옵션을 설정한다.
if [ $staging != "0" ]; then staging_arg="--staging"; fi

# Certbot 를 사용하여 Let's Encrypt 인증서를 요청한다. 
docker-compose run --rm --entrypoint "\ 
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### NGINX 재시작 함미다 . ..." 
# 실행중인 reverse_proxy 컨테이너에서 nginx 재시작
docker-compose exec  reverse_proxy nginx -s reload
