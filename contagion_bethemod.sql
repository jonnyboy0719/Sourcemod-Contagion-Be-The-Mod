CREATE TABLE IF NOT EXISTS `contagion_bethemod` (
  `uid` varchar(255) NOT NULL DEFAULT 'BOT',
  `type` varchar(255) DEFAULT NULL,
  `model` varchar(255) DEFAULT NULL,
  `group` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`uid`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;