CREATE TABLE `entries` (
 `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
 `date` datetime NOT NULL,
 `uuid` char(36) NOT NULL,
 `latitude` decimal(8,5) NOT NULL,
 `longitude` decimal(8,5) NOT NULL,
 `speed` smallint(5) unsigned NOT NULL,
 `altitude` smallint(6) NOT NULL,
 `heading` smallint(5) unsigned NOT NULL,
 `accuracy` smallint(5) unsigned NOT NULL,
 `battery` tinyint(3) unsigned DEFAULT NULL,
 PRIMARY KEY (`id`),
 KEY `date` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
