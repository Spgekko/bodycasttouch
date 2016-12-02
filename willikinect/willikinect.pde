

/**
 * Processing Skeleton Interface with Watchout
 * by Kenny Lozowski with Willi Franco
 * 
 * This will receive 3D hand position information from the Kinect Library's skeleton tracker
 * It will check those hand positions against a 'hotspot position' (within a tolerance threshold
 * On the basis of being close enough to hotspots it sends some commands over UDP to Dataton Watchout
 */
 
// first we import the libraries we'll need: a the javaArray utility library, the processing network library, a UDP packet sender, and Kinectv2 Library 
import KinectPV2.*;
import processing.net.*;
import hypermedia.net.*;

//now define some program constants


static final boolean LOG_STATE_CHANGES = true; //shall we log hotspot changes in state?
static final boolean SEND_UDP_COMMANDS = true; //shall we send UDP commands to watchout
static final int TX_PORT = 56001; //the port we transmit from
static final int WATCHOUT_PORT = 3040; //the port Watchout listens on for network commands
static final String SOURCE_IP = "127.0.0.1"; // this computer's ip. we're using the loopback IP, you could also set this to your computer's DHCP acquired IP
static final String DEST_IP = "127.0.0.1"; // the destination IP. if you're sending this in-computer this is also the loopback IP
boolean figure1LeftHandLogging = false; //shall we log the figure 1 left hand data to gather hotspot locations with this kinect position -- controlled with the l key
JSONArray hotspotDefinitions; //the object to hold the JSON hotspots array
boolean[][][] activeHotspots; //an array to determine which hotspots are active
UDP udpTX; //the UDP transmission object
KinectPV2 kinect; // the Kinect library object

//this is the program setup, it runs once

void setup() {
  size(1024,768);  // create a program window
  udpTX=new UDP(this, TX_PORT, SOURCE_IP); //instantiate the UDP transmission object
  udpTX.log(true); //set the UDP transmission object to log
  hotspotDefinitions = loadJSONArray("hotspots.json"); //load the hotspot Definitions from the JSON file
 
  initializeHotspots();
  kinect = new KinectPV2(this); //instantiate the Kinect object
  kinect.enableColorImg(true); // allows us to see what's going on
  kinect.enableSkeleton3DMap(true);   //enable 3d  with (x,y,z) position
  kinect.init(); //do an initialization of the kinect
}

//this runs on a loop whose speed is set by the framerate
void draw() { 
  background(0); //set a black background  
  image(kinect.getColorImage(), 0, 0, 320, 240); // a photo of what's happening in the kinect for reference
  getKinectFrame(); //call the getKinectFrame function
}

//this function is called by the processing framework every time a key is pressed
void keyPressed() {
  if (key == 108) { // if the key is 'l'
    figure1LeftHandLogging = !figure1LeftHandLogging; // toggle figure 1 left hand logging so you can set hotspots
  } 
}

void initializeHotspots() {
  activeHotspots = new boolean[6][2][hotspotDefinitions.size()]; //set the size of the active hotspots array -- first dimension is number of kinect figures, second is 2 hands, 3rd is number of hotspots
  for (int i=0;i<6;i++) {
    for (int j=0;j<2;j++) {
        for (int k=0;k<hotspotDefinitions.size();k++) {
          activeHotspots[i][j][k] = false;
        }
    }
  }
}

//this function gets the fingertip coordinates from all figures, both hands
void getKinectFrame() {
 ArrayList<KSkeleton> skeletonArray =  kinect.getSkeleton3d(); // get all the skeletons
  int figureNum = 1; // define the figure iterator
  for (int i = 0; i < skeletonArray.size(); i++) { //iterate through the skeletons found
    KSkeleton skeleton = (KSkeleton) skeletonArray.get(i); //grab this skeleton
    if (skeleton.isTracked()) { // if this skeleton is actually tracking
      KJoint[] joints = skeleton.getJoints(); // get an array of  all its joints
      KJoint leftHand = joints[KinectPV2.JointType_HandTipLeft]; // define the left hand tip
      KJoint rightHand = joints[KinectPV2.JointType_HandTipRight]; // define the right hand tip
      checkHotspots(i,0,leftHand.getX(),leftHand.getY(),leftHand.getZ()); // call this function to check this figure's left hand against the hot spots
      checkHotspots(i,1,rightHand.getX(),rightHand.getY(),rightHand.getZ()); // call the same function with the right hand position arguments to check this figure's left hand against the hot spots
      if ((figureNum == 1) && (figure1LeftHandLogging)) println("Figure 1 Left Hand: "+leftHand.getX()+" "+leftHand.getY()+" "+leftHand.getZ()); // log the left hand tip
      figureNum++; //increase the figure iterator
    }
  }
}

//this function checks one 3D fingertip coordinate taken from the kinect against all the hotspots and sends commands to watchout if the hotspot state changes
void checkHotspots(int whichFigure, int whichHand, float x, float y, float z) {
  for (int i = 0; i < hotspotDefinitions.size(); i++) { //iterate through all the hotspots in the definitions
    boolean isIn = false; //is the kinect location 'in' the hotspot threshold
    JSONObject hotspot = hotspotDefinitions.getJSONObject(i); //get the hotspot definition defined by the iterator
    float deltaX = x - hotspot.getFloat("x"); //get this hotspot's x position
    float deltaY = y - hotspot.getFloat("y"); //get this hotspot's y position
    float deltaZ = z - hotspot.getFloat("z"); //get this hotspot's z position
    double d = Math.sqrt(Math.pow(deltaX,2)+Math.pow(deltaY,2)+Math.pow(deltaZ,2)); //calculate the 3D distance between the current hand tip and this hotspot
    if ((float) d < hotspot.getFloat("threshold")) { //if the distance is within this hotspot's threshold
      isIn = true; //we're in
      if (activeHotspots[whichFigure][whichHand][i] != isIn) { //only when the state changed since the last frame
          activeHotspots[whichFigure][whichHand][i] = true; //match the hotspot state with the change
          String inCommand = hotspot.getString("incommand");
          if (LOG_STATE_CHANGES) println("We activated hotspot: "+hotspot.getString("name")); //if we're logging tell us we hit it
          if ((!inCommand.equals("")) && (SEND_UDP_COMMANDS)) udpTX.send(inCommand,DEST_IP,WATCHOUT_PORT); //if we're sending to watchout send it
      }
    } else {
      isIn = false;
      if (activeHotspots[whichFigure][whichHand][i] != isIn) { //only when the state changed since the last frame
          activeHotspots[whichFigure][whichHand][i] = false; //match the hotspot state with the change
          String outCommand = hotspot.getString("outcommand");
          if (LOG_STATE_CHANGES) println("We de-activated hotspot: "+hotspot.getString("name")); //if we're logging tell us we hit it
          if ((!outCommand.equals("")) && (SEND_UDP_COMMANDS)) udpTX.send(outCommand,DEST_IP,WATCHOUT_PORT); //if we're sending to watchout send it
      }
    }
  }
}