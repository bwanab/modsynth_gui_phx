// SynthCanvas Phoenix LiveView Hook
export const SynthCanvas = {
  mounted() {
    this.isDragging = false;
    this.dragTarget = null;
    this.dragOffset = { x: 0, y: 0 };
    this.svg = this.el;
    
    // Add event listeners for drag and drop
    this.handleMouseDown = this.handleMouseDown.bind(this);
    this.handleMouseMove = this.handleMouseMove.bind(this);
    this.handleMouseUp = this.handleMouseUp.bind(this);
    
    this.svg.addEventListener('mousedown', this.handleMouseDown);
    document.addEventListener('mousemove', this.handleMouseMove);
    document.addEventListener('mouseup', this.handleMouseUp);
    
    // Prevent default drag behavior on SVG elements
    this.svg.addEventListener('dragstart', (e) => e.preventDefault());
  },
  
  destroyed() {
    this.svg.removeEventListener('mousedown', this.handleMouseDown);
    document.removeEventListener('mousemove', this.handleMouseMove);
    document.removeEventListener('mouseup', this.handleMouseUp);
  },
  
  handleMouseDown(e) {
    // Check if we clicked on a node
    const nodeGroup = e.target.closest('g[id^="node-"]');
    if (!nodeGroup) return;
    
    e.preventDefault();
    e.stopPropagation();
    
    this.isDragging = true;
    this.dragTarget = nodeGroup;
    
    // Get the current transform of the node
    const transform = nodeGroup.getAttribute('transform');
    const match = transform.match(/translate\(([^,]+),([^)]+)\)/);
    const currentX = match ? parseFloat(match[1]) : 0;
    const currentY = match ? parseFloat(match[2]) : 0;
    
    // Get mouse position relative to SVG
    const rect = this.svg.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Calculate offset from mouse to node position
    this.dragOffset = {
      x: mouseX - currentX,
      y: mouseY - currentY
    };
    
    // Add visual feedback
    nodeGroup.style.opacity = '0.8';
  },
  
  handleMouseMove(e) {
    if (!this.isDragging || !this.dragTarget) return;
    
    e.preventDefault();
    
    // Get mouse position relative to SVG
    const rect = this.svg.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Calculate new position (updated for new node size: 140x80)
    const newX = Math.max(0, Math.min(mouseX - this.dragOffset.x, this.svg.viewBox.baseVal.width - 140));
    const newY = Math.max(0, Math.min(mouseY - this.dragOffset.y, this.svg.viewBox.baseVal.height - 80));
    
    // Update node position
    this.dragTarget.setAttribute('transform', `translate(${newX}, ${newY})`);
  },
  
  handleMouseUp(e) {
    if (!this.isDragging || !this.dragTarget) return;
    
    e.preventDefault();
    
    // Get final position
    const transform = this.dragTarget.getAttribute('transform');
    const match = transform.match(/translate\(([^,]+),([^)]+)\)/);
    const finalX = match ? parseFloat(match[1]) : 0;
    const finalY = match ? parseFloat(match[2]) : 0;
    
    // Get node ID from the group element
    const nodeId = this.dragTarget.id.replace('node-', '');
    
    // Send position update to LiveView
    this.pushEvent('node_moved', {
      id: parseInt(nodeId),
      x: finalX,
      y: finalY
    });
    
    // Remove visual feedback
    this.dragTarget.style.opacity = '1';
    
    // Reset drag state
    this.isDragging = false;
    this.dragTarget = null;
    this.dragOffset = { x: 0, y: 0 };
  }
};