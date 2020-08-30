FROM ruby:2-alpine
MAINTAINER Dr. Michael Specht <specht@quelltextschmiede.de>

RUN apk update && apk upgrade
RUN apk add curl bash curl-dev ruby-dev build-base mysql-dev sqlite-dev imagemagick git tzdata && rm -rf /var/cache/apk/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
RUN bundle install
USER 1000:1000
