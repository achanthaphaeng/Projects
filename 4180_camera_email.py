from picamera import PiCamera
from time import sleep
import threading
import serial
import smtplib, ssl
import RPi.GPIO as GPIO
import time
import board
import adafruit_lsm9ds1

#i2c = board.I2C()
#sensor = adafruit_lsm9ds1.LSM9DS1_I2C(i2c)
#GPIO Mode (BOARD / BCM)
GPIO.setmode(GPIO.BCM)
 
#set GPIO Pins
GPIO_TRIGGER = 18
GPIO_ECHO = 24
 
#set GPIO direction (IN / OUT)
GPIO.setup(GPIO_TRIGGER, GPIO.OUT)
GPIO.setup(GPIO_ECHO, GPIO.IN)
 
def dist():
    # set Trigger to HIGH
    GPIO.output(GPIO_TRIGGER, True)
 
    # set Trigger after 0.01ms to LOW
    time.sleep(0.00001)
    GPIO.output(GPIO_TRIGGER, False)
 
    StartTime = time.time()
    StopTime = time.time()
 
    # save StartTime
    while GPIO.input(GPIO_ECHO) == 0:
        StartTime = time.time()
 
    # save time of arrival
    while GPIO.input(GPIO_ECHO) == 1:
        StopTime = time.time()
 
    # time difference between start and arrival
    TimeElapsed = StopTime - StartTime
    # multiply with the sonic speed (34300 cm/s)
    # and divide by 2, because there and back
    distance = (TimeElapsed * 34300) / 2
    #print ("Measured Distance = %.1f cm" % distance)
    #send email if too sonar detects something too close
    if distance < 12:
        port = 465  # For SSL
        smtp_server = "smtp.gmail.com"
        sender_email = "alex4180test@gmail.com"  # Enter your address
        receiver_email = "alex4180test@gmail.com"  # Enter receiver address
        password = "abcD1234!"
        message = """\
        Subject: Hi there

        You seem to be too close to something."""
        
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(smtp_server, port, context=context) as server:
            server.login(sender_email, password)
            server.sendmail(sender_email, receiver_email, message)
    return distance

i = 0        
new_dist = []
while True:
    cam = PiCamera()
    dist_thread = threading.Thread(target=dist)
    dist_thread.start()
    dist_thread.join()
    new_dist.append(dist())
    print(new_dist)
    if new_dist[i] > new_dist[i - 1] + 2.0:
        cam.start_preview()
        time.sleep(5)
        cam.stop_preview()
    i += 1
    print(i)
    cam.close()
    time.sleep(3)
 