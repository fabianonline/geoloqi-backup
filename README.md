Geoloqi-Backup
==============

Beschreibung
------------

Dieses Tool lädt per Cronjob alle zu einem Useraccount verfügbaren Positionsdaten herunter und speichert sie in einer MySQL-Datenbank. Zusätzlich wird eine Map-Ansicht erzeugt, die alle bisher aufgezeichneten Punkte auf einer OSM-Karte anzeigt.

Installation
------------

Diese App ist in Ruby geschrieben; folgende Gems werden benötigt:
* active_record
* yaml
* geoloqi
* RMagick
* getopt

Auf einem MySQL-Server wird eine Tabelle namens `entries` benötigt; der SQL-Code, um diese zu erzeugen, ist in db.schema.sql abgelegt.

Die Datei `config.example.yml` muss zu `config.yml` kopiert oder umbenannt werden. Dort müssen die Daten zum MySQL-Server hinterlegt werden. Außerdem wird ein Zugangstoken zur Geoloqi-API benötigt, dieses findet man (etwas versteckt) bei [Geoloqi](https://developers.geoloqi.com/client-libraries/cURL). (Nur, wenn man eingeloggt ist; benötigt wird der String unter "Your Access Token".)

Anwendung
---------

Anschließend kann das Skript von Hand oder per Cronjob gestartet werden; es wird dann alle bei Geoloqi vorliegenden und noch nicht bekannten Datensätze abrufen, in der lokalen Datenbank sichern und anschließend eine Datei `image.png` mit einer Grafik alles besuchter Punkte sowie `image.html` mit der Kombination aus OSM und der Grafikdatei erzeugen.
