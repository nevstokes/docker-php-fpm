# PHP FPM Docker Image

Heavily customised [UPX](https://upx.github.io)-compressed image for PHP FPM.

Includes PDO Postgresql driver and curl, and has bcmath, mbstring and opcode modules enabled but no image manipulation or PEAR support.

Additionally, the third-party extensions [APCu](https://github.com/krakjoe/apcu), [Redis](https://github.com/phpredis/phpredis) and [Igbinary](https://github.com/igbinary/igbinary) are compiled in.