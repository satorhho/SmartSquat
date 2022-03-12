from flask import Flask, render_template, Response, request
import cv2
import mediapipe as mp
import time
import numpy as np
from matplotlib import pyplot as plt
import math
import os
import pathlib


#instatiate flask app  
app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

camera = cv2.VideoCapture(0, cv2.CAP_DSHOW)
# camera = cv2.VideoCapture("http://192.168.100.2:8080/video")

mpDraw = mp.solutions.drawing_utils
mpPose = mp.solutions.pose
pose = mpPose.Pose()

recording = []
segments = []

def save_imgs():
    counter = 0
    for i in segments:
        cv2.imwrite(f"{os.path.abspath(os.getcwd())}\\cnn_inputs\\input{counter}.png", i[0])
        counter += 1
    
    print("Images saved!")
    recording.clear()
    segments.clear()

def segmentize(recording_arr):
    segments.append(recording_arr[0]) # top_1
    segments.append(recording_arr[math.floor(len(recording_arr)/2)]) # mid_1
    segments.append(recording_arr[len(recording_arr)-2]) # bot_1
    
    print("Passed")
    return True

def gen_frames():  # generate frame by frame from camera
    initial_time = time.time()
    initial_ankle_pos = 0.01
    isTimed = False
    isRecording = False
    tmp_lmval =  0.1

    monitor_val = 0.01
    isTracking = False
    rec_this = 0
    while True:
        ret, frame = camera.read() 

        imgRGB = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = pose.process(imgRGB)

        if results.pose_landmarks:
            mpDraw.draw_landmarks(frame, results.pose_landmarks, mpPose.POSE_CONNECTIONS)
            for id, lm in enumerate(results.pose_landmarks.landmark):
                h, w, c = frame.shape


                if id == 11: 
                    tmp_lmval = round(lm.x, 1)
                
                
                if (not isTimed): # Set timer for 2 seconds
                    initial_time = time.time()
                    if id == 11: 
                        initial_ankle_pos = round(lm.x, 1)
                else: 
                    if time.time() >= initial_time+2:
                        isRecording = True
                    
                    
                if tmp_lmval == initial_ankle_pos: 
                    isTimed = True
                else:
                    isTimed = False
                
                if isRecording:
                    if id == 11:
                        recording.append((frame, round(lm.y, 1)))
                        #monitor_val = round(lm.x, 1)
                        rec_this = round(lm.y, 1)
                        
                        if monitor_val > rec_this:
                            isRecording = False
                            isTracking = segmentize(recording) 
                            monitor_val = 0.01
                            isTimed = False
                            initial_time = time.time()
                            initial_time2 = time.time()
                            
                        monitor_val = round(lm.y, 1)
                
                if isTracking:
                    if id == 11:
                    
                        if monitor_val < round(lm.y, 1) or recording[0][1] == round(lm.y, 1):
                            isTracking = False
                            recording.append((frame, round(lm.y, 1)))
                            segments.append(recording[len(recording)-1])
                            save_imgs()
                            isRecording = False
                            isTimed = False
                            initial_time = time.time()
                            initial_time2 = time.time()
                            monitor_val = 0.01
                            print("Passed2")
            frame = cv2.flip(frame,1)
            cv2.putText(frame, f"{isRecording}prev:{monitor_val}curr:{rec_this}isTr{isTracking}", (40, 50), cv2.FONT_HERSHEY_PLAIN, 2, (255, 0, 0), 2)
                
                            
            try:
                ret, buffer = cv2.imencode('.jpg', frame)
                frame = buffer.tobytes()
                yield (b'--frame\r\n'
                        b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
            except Exception as e:
                pass
                


@app.route('/video')
def video():
    return Response(gen_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')


if __name__ == '__main__':
    app.run(host="0.0.0.0")
