package org.knowrob.vis;

import java.util.Map;
import java.util.LinkedHashMap;
import java.util.concurrent.ConcurrentHashMap;

import org.apache.commons.logging.Log;
import org.ros.message.Duration;
import org.ros.namespace.GraphName;
import org.ros.node.AbstractNodeMain;
import org.ros.node.ConnectedNode;
import org.ros.node.topic.Publisher;
import org.ros.internal.loader.CommandLineLoader;
import org.ros.node.DefaultNodeMainExecutor;
import org.ros.node.NodeConfiguration;
import org.ros.node.NodeMainExecutor;
import com.google.common.collect.Lists;

import visualization_msgs.Marker;
import visualization_msgs.MarkerArray;

/**
 * Visualization marker node. Used for generating and publishing marker messages
 * on the topic "/visualization_marker_array".
 * The messages can be displayed by visualization tools such as openEASE or RViz.
 * 
 * @author Daniel Beßler
 */
public class MarkerPublisher extends AbstractNodeMain {
	/**
	 * The ROS message publisher if connected, else null
	 */
	private Publisher<MarkerArray> pub = null;
	private Publisher<MarkerArray> highlighter = null;
	/**
	 * The ROS node if connected, else null
	 */
	protected ConnectedNode node = null;
	/**
	 * Logger of ROS node if connected, else null
	 */
	private Log log = null;
	
	/**
	 * Store the markers to be published
	 */
	protected Map<String, MarkerObject> markers;
	/**
	 * Store all added markers
	 */
	protected Map<String, MarkerObject> markersCache;
	
	/**
	 * Counter for marker IDs
	 */
	private static int id = 0;

	private static MarkerPublisher instance = null;
	
	public static MarkerPublisher get() {
		if(instance==null) instance = new MarkerPublisher();
		return instance;
	}

	private MarkerPublisher() {
		markers =  new LinkedHashMap<String, MarkerObject>();
		markersCache =  new ConcurrentHashMap<String, MarkerObject>(8, 0.9f, 1);
	}

	@Override
	public void onStart(final ConnectedNode connectedNode) {
		node = connectedNode;
		pub = connectedNode.newPublisher("/visualization_marker_array", visualization_msgs.MarkerArray._TYPE);
		highlighter = connectedNode.newPublisher("/marker_highlight", visualization_msgs.MarkerArray._TYPE);
		log = connectedNode.getLog();
	}

	@Override
	public GraphName getDefaultNodeName() {
		return GraphName.of("knowrob_marker");
	}
	
	public MarkerObject createMarker(String identifier) {
		waitForNode();
		MarkerObject marker = getMarker(identifier);
		if(marker!=null) return marker;
		marker = markers.get(identifier);
		if(marker!=null) {
			// marker was removed and re-added before marker remove message was send,
			// just ignore the remove message in this case
			markersCache.put(identifier, marker);
			return marker;
		}

		Marker m = node.getTopicMessageFactory().newFromType(visualization_msgs.Marker._TYPE);
		m.getHeader().setFrameId("/map"); // FIXME: set in prolog
		m.getHeader().setStamp(node.getCurrentTime());
		m.setNs(identifier);
		m.setId(id++);
		m.setAction(Marker.ADD);
		m.setLifetime(new Duration());
		
		marker = new MarkerObject(identifier, m, this);
		if(marker.hasVisual()) {
			synchronized (markers) {
				markers.put(identifier, marker);
			}
		}
		synchronized (markersCache) {
			markersCache.put(identifier, marker);
		}
		
		return marker;
	}
	
	public MarkerObject getMarker(String identifier) {
		return markersCache.get(identifier);
	}
	
	public void eraseMarker(String identifier) {
		try {
			MarkerObject m = markersCache.remove(identifier);
			if(m!=null) {
				m.getMessage().setAction(Marker.DELETE);
				markers.put(identifier,m);
			}
		}
		catch(Exception exc) {
			log.error("Failed to remove marker.", exc);
		}
	}
	
	public void eraseMarker(MarkerObject marker) {
		eraseMarker(marker.getIdentifier());
	}
	
	public void eraseAllMarker() {
		synchronized (markersCache) {
			while(!markersCache.keySet().isEmpty())
				eraseMarker(markersCache.keySet().iterator().next());
		}
	}
	
	public void publishMarker() {
		try {
			waitForNode();

			synchronized (markers) {
				MarkerArray arr = pub.newMessage();
				for(MarkerObject mrk : markers.values()) {
					if(mrk.hasVisual()) {
						arr.getMarkers().add(mrk.getMessage());
						if(mrk.getMessage().getAction()==Marker.DELETE) mrk.isPublished=false;
						else mrk.isPublished=true;
					}
				}
				pub.publish(arr);
				markers.clear();
			}
		}
		catch (Exception exc) {
			log.error("Failed to publish marker.", exc);
		}
	}
	
	public void highlightMarker(MarkerObject mrk) {
		try {
			waitForNode();

			MarkerArray arr = pub.newMessage();
			arr.getMarkers().add(mrk.getMessage());
			highlighter.publish(arr);
		}
		catch (Exception exc) {
			log.error("Failed to highlight marker.", exc);
		}
	}
	
	public void republishMarker() {
		try {
			waitForNode();

			MarkerArray arr = pub.newMessage();
			synchronized (markersCache) {
				for(MarkerObject mrk : markersCache.values()) {
					if(mrk.hasVisual()) arr.getMarkers().add(mrk.getMessage());
				}
			}
			pub.publish(arr);
		}
		catch (Exception exc) {
			log.error("Failed to publish marker.", exc);
		}
	}

	public void queueRepublish(MarkerObject markerObject) {
		if(markerObject.getHasVisual() && !markerObject.isHidden()) {
			synchronized (markers) {
				markers.put(markerObject.getIdentifier(), markerObject);
			}
		}
	}

	public void unqueueRepublish(MarkerObject markerObject) {
		synchronized (markers) {
			markers.remove(markerObject.getIdentifier());
		}
	}
	
	public ConnectedNode getNode(){
		waitForNode();
		return this.node;
	}

	private void waitForNode() {
		try {
			while(node == null || pub == null) Thread.sleep(200);
		}
		catch (InterruptedException e) {
			e.printStackTrace();
		}
	}
    
    public static void runNode(AbstractNodeMain node, String[] args) {
        CommandLineLoader loader = new CommandLineLoader(Lists.newArrayList(args));
        NodeConfiguration nodeConfiguration = loader.build();

        NodeMainExecutor nodeMainExecutor = DefaultNodeMainExecutor.newDefault();
        nodeMainExecutor.execute(node, nodeConfiguration);
    }
}
