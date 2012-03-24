Geoloqi-Backup
==============

Beschreibung
------------

Dieses Tool lädt per Cronjob alle zu einem Useraccount verfügbaren Positionsdaten herunter und speichert sie in einer MySQL-Datenbank. 
Zusätzlich wird eine Map-Ansicht erzeugt, die alle bisher aufgezeichneten Punkte auf einer OSM-Karte anzeigt.

Installation
------------

Diese App ist in Ruby geschrieben; folgende Gems werden benötigt:
* active_record
* yaml
* geoloqi
* RMagick
* getopt
* sinatra
* sinatra-activerecord

Die Datei `config.example.yml` muss zu `config.yml` kopiert oder umbenannt werden. Dort müssen besonders Zugangsdaten zum MySQL-Server
hinterlegt werden. Außerdem wird ein Zugangstoken zur Geoloqi-API benötigt, dieses findet man (etwas versteckt) bei 
[Geoloqi](https://developers.geoloqi.com/client-libraries/cURL). (Nur, wenn man eingeloggt ist; benötigt wird der String unter "Your Access Token".)
Die Tabellenstruktur in der Datenbank kann dann per `rake db:migrate` erzeugt werden.

Anwendung
---------

Anschließend kann das Skript von Hand oder per Cronjob mit dem Parameter `--update` gestartet werden; es wird dann alle bei Geoloqi 
vorliegenden und noch nicht bekannten Datensätze abrufen und in der lokalen Datenbank sichern.
Zudem kann Geoloqi als Sinatra-App per Webbrowser aufgerufen werden; dort kann man dann frei auf der Karte herumscrollen und so.
