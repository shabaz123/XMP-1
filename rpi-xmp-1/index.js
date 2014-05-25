#!/usr/bin/env node

var app = require('http').createServer(handler)
  , io = require('socket.io').listen(app)
  , fs = require('fs')

app.listen(8081);

// variables
var child=require('child_process');
var prog;
var step = new Array(101); // used for storing and playing back
var steptime = new Array(101);
var smode; // stores the current command
var elapsed=0; // stores how long an action has been running for
var recmode=0;
var playmode=0;
var stepnum=0;
var steptot=0;
var idle=[1460, 1440]; // servo idle values (trim to suit)

var progpath='/home/pi/development/xmos/';

xmos_servo(idle);

// HTML handler
function handler (req, res)
{
	console.log('url is '+req.url.substr(1));
	reqfile=req.url.substr(1);
	if (reqfile != "xmp-logo.png")
	{
		reqfile="index.html"; // only allow this file for now
	}
	fs.readFile(progpath+reqfile,
  function (err, data)
  {
    if (err)
    {
      res.writeHead(500);
      return res.end('Error loading index.html');
    }
    res.writeHead(200);
    res.end(data);
  });
}

function xmos_servo(v)
{
	vv=new Array(2);
	vv[0]=v[0];
	vv[1]=v[1];
	prog=child.exec(progpath+'xmos_servo '+v[0]+' '+v[1]), function (error, stdout, stderr){};
	prog.on('exit', function(code)
	{
		console.log('app complete');
	});
	
}

// serviceServo - handles the servo action over time
// It just times how long the action has occurred for,
// and also steps through any learnt actions according
// to the time schedule if in playback mode
function serviceServo()
{
	elapsed++;
	if (playmode)
	{
		if(elapsed>=steptime[stepnum])
		{
			stepnum++;
			elapsed=0;
			if (stepnum<steptot)
			{
				ret=handleCommand(step[stepnum]);
			}
			else
			{
				playmode=0;
				xmos_servo(idle);
			}
		}
	}
}

function recordStep(cmd)
{
	if (recmode)
	{
  	step[stepnum]=smode;
  	if (stepnum==0) elapsed=0;
  	steptime[stepnum]=elapsed;
  	stepnum++;
  	elapsed=0;
  	if (stepnum>99)
  	{
  		recmode=0;
  	}
  }
  smode=cmd;
}

function handleCommand(command)
{
	var valarray = new Array(2);
	
  if ((command.substring(0,3)=="fwd") | (command.substring(0,3)=="rev"))
  {
  	recordStep(command); // record the last step, and prepare for the new step
  	speed=command.substring(3,4);
  	sp_int=parseInt(speed);
  	if (command.substring(0,3)=="rev")
  	{
  		dir=-1;
  	}
  	else
  	{
  		dir=1;
  	}
  	// the values here are trimmed for the servos.
  	// trimming may be different in each direction!
  	if (dir==1) // fwd
  	{
  		if (sp_int==1)
  		{
  			valarray[0]=idle[0]+50;
  			valarray[1]=idle[1]-40;
  		}
  		else if (sp_int==2)
  		{
  			valarray[0]=idle[0]+100;
  			valarray[1]=idle[1]-90;
  		}
  		else if (sp_int==3)
  		{
  			valarray[0]=idle[0]+500;
  			valarray[1]=idle[1]-500;
  		}
  	}
  	else
  	{
  		// rev
  		if (sp_int==1)
  		{
  			valarray[0]=idle[0]-50;
  			valarray[1]=idle[1]+60;
  		}
  		else if (sp_int==2)
  		{
  			valarray[0]=idle[0]-100;
  			valarray[1]=idle[1]+110;
  		}
  		else if (sp_int==3)
  		{
  			valarray[0]=idle[0]-500;
  			valarray[1]=idle[1]+500;
  		}
  	}  	
  	xmos_servo(valarray);
  	ret='done';
  	return ret;
 	}
	else if ((command.substring(0,4)=="left") | (command.substring(0,5)=="right"))
 	{
 		recordStep(command); // record the last step, and prepare for the new step
 		if (command.substring(0,4)=="left")
 		{
 			dir=-1;
 			speed=command.substring(4,5);
 		}
 		else
 		{
 			dir=1;
 			speed=command.substring(5,6);
 		}
 		sp_int=parseInt(speed);
 		delta=0;
  	if (sp_int==1)
  	{
  		delta=30;
  	}
  	else if (sp_int==2)
  	{
  		delta=100;
  	}

  	valarray[0]=idle[0]+dir*delta;
  	valarray[1]=idle[0]+dir*delta;
 		
 		xmos_servo(valarray);
 		ret='done';
  	return ret;
	}
	else if (command.substring(0,7)=="stoprec")
	{
		if (recmode)
		{
			recmode=0;
			if (smode=='stop')
			{
				// already stopped
			}
			else
			{
				recordStep('stop');
				xmos_servo(idle);
			}
			steptot=stepnum;
			stepnum=0;
			ret='done';
			console.log('stored '+steptot+' steps');
		}
		else
		{
			ret='error';
		}
  	return ret;
	}
	else if (command.substring(0,4)=="stop")
	{
		recordStep(command); // record the last step, and prepare for the new step
  	xmos_servo(idle);
  	ret='done';
  	return ret;
	}
	else if (command.substring(0,3)=="rec")
	{
		if (recmode==0)
		{
			elapsed=0;
			recmode=1;
			stepnum=0;
			steptot=0;
			smode="stop";
			xmos_servo(idle);
			ret='done';
		}
		else
		{
			ret='already'; // we are already recording
		}
  	return ret;
	}
	else if (command.substring(0,4)=="play")
	{
		if ((steptot>0) && (recmode==0))
		{
			if (playmode==1)
			{
				ret='already';
			}
			else
			{
				stepnum=0;
				elapsed=0;
				playmode=1;
				ret='done';
			}
		}
		else
		{
			// nothing to play, or we are still in learning mode
			ret='error';
		}
  	return ret;
	}

}

// set up the 'tick' for serviceServo
s_id=setInterval(serviceServo, 100); // 100msec reaction time for learn/play

// Socket.IO comms handling
// A bit over-the-top but we use some handshaking here
// We advertise message 'status stat:idle' to the browser once,
// and then wait for message 'action command:xyz'
// We handle the action xyz and then emit the message 'status stat:done'
io.sockets.on('connection', function (socket)
{
	socket.emit('status', {stat: 'idle'});
	socket.on('action', function (data)
	{
    console.log(data);
    cmd=data.command;
    console.log(cmd);
    // perform the desired action based on 'command':
    ret=handleCommand(cmd);
    socket.emit('status', {stat: ret});
		

  }); // end of socket.on('action', function (data)

}); // end of io.sockets.on('connection', function (socket)


