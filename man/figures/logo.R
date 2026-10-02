# Generate the soccerrsr hex sticker from the repository root:
#   Rscript man/figures/logo.R
# Requires ggplot2, hexSticker, and an R graphics device supporting gradients.
# Output: man/figures/logo.png (600 dpi, transparent outside the hexagon).
# Original soccer-ball geometry: a truncated icosahedron projected onto a sphere.

library(ggplot2)
library(hexSticker)
phi <- (1 + sqrt(5))/2
v <- rbind(as.matrix(expand.grid(a=c(-1,1), b=c(-phi,phi)))[,c(1,2)])
v <- rbind(cbind(0,v), cbind(v[,1],v[,2],0), cbind(v[,2],0,v[,1]))
d <- as.matrix(dist(v))
adj <- abs(d-2)<1e-6
faces <- list()
for(i in 1:12) {
  ns <- which(adj[i,])
  faces[[length(faces)+1]] <- list(p=t(sapply(ns,function(j) (2*v[i,]+v[j,])/3)), black=TRUE)
}
for(i in 1:10) for(j in (i+1):11) for(k in (j+1):12) {
  if(adj[i,j] && adj[j,k] && adj[k,i]) {
    pairs <- rbind(c(i,j),c(j,i),c(j,k),c(k,j),c(k,i),c(i,k))
    faces[[length(faces)+1]] <- list(p=t(apply(pairs,1,function(q) (2*v[q[1],]+v[q[2],])/3)),black=FALSE)
  }
}
unit <- function(x) x/sqrt(sum(x*x))
cross <- function(a,b) c(a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1])
z <- unit(v[1,])
x <- unit(cross(c(0,0,1),z)); y <- cross(z,x)
rot <- cbind(x,y,z)
polys <- list()
for(id in seq_along(faces)) {
  f <- faces[[id]]; p <- f$p
  normal <- unit(colMeans(p)); u <- unit(p[1,]-colMeans(p)); w <- cross(normal,u)
  p <- p[order(atan2(p %*% w,p %*% u)),,drop=FALSE]
  dense <- do.call(rbind,lapply(seq_len(nrow(p)),function(i) {
    j <- i %% nrow(p)+1
    t(sapply(seq(0,1,length.out=31),function(t) unit((1-t)*p[i,]+t*p[j,])))
  })) %*% rot
  if(max(dense[,3])<=0) next
  # Project hidden edge points onto the silhouette to clip at the visible hemisphere.
  hidden <- dense[,3]<0
  dense[hidden,1:2] <- dense[hidden,1:2,drop=FALSE]/sqrt(rowSums(dense[hidden,1:2,drop=FALSE]^2))
  polys[[length(polys)+1]] <- data.frame(x=dense[,1],y=dense[,2],id=id,fill=if(f$black) '#171717' else '#FFFFFF',depth=mean(dense[,3]))
}
polys <- polys[order(sapply(polys,function(p) p$depth[1]))]
polys <- do.call(rbind,polys)
polys$id <- factor(polys$id,levels=unique(polys$id))
underball <- polys
underball$x <- underball$x * 0.5376
underball$y <- underball$y * 0.5376 - 0.075
circle_angle <- seq(0, 2*pi, length.out=721)
white_backing <- data.frame(x=cos(circle_angle), y=sin(circle_angle))
ball <- ggplot(polys,aes(x,y,group=id)) +
  geom_polygon(data=white_backing,aes(x,y),inherit.aes=FALSE,fill='#FFFFFF',color=NA) +
  geom_polygon(data=underball,aes(fill=fill),color='#000000',linewidth=0.14) +
  geom_polygon(aes(fill=fill),color='#414141',alpha=0.78,linewidth=0.18,linejoin='round') +
  annotate('text', x=0, y=0.495, label='soccer-rs', family='sans', fontface='bold', size=1.8, color='#454F55') +
  scale_fill_identity() + coord_fixed(xlim=c(-1.03,1.03),ylim=c(-1.03,1.03),expand=FALSE) + theme_void() + theme_transparent()
logo <- sticker(subplot=ball,s_x=1,s_y=1.18,s_width=1.24,s_height=1.24,package='soccerrsr',p_x=0.94,p_y=0.47,p_color='#FFFFFF',p_family='sans',p_fontface='bold.italic',p_size=4.8,h_fill=grid::linearGradient(colours=c('#BB0E3D','#900B32','#30051A'),stops=c(0,0.40,1),x1=0.5,y1=1,x2=0.5,y2=0),h_color='#99CAE4',h_size=1.0,spotlight=FALSE,url='https://github.com/danielruss/soccerrsr',u_color='#FFFFFF',u_family='sans',u_size=1.05,filename='man/figures/logo.png',dpi=600)

# Horizontal red light lines, inset from the hexagon border.
light_y <- seq(0.22, 1.82, by=0.16)
light_halfwidth <- ifelse(abs(light_y-1)<=0.5, sqrt(3)/2, sqrt(3)*(1-abs(light_y-1))) - 0.04
light_lines <- data.frame(x=1-light_halfwidth,xend=1+light_halfwidth,y=light_y,yend=light_y)
light_glow <- geom_segment(data=light_lines,aes(x=x,y=y,xend=xend,yend=yend),inherit.aes=FALSE,color='#FF7087',linewidth=0.4,alpha=0.04,lineend='round')
light_core <- geom_segment(data=light_lines,aes(x=x,y=y,xend=xend,yend=yend),inherit.aes=FALSE,color='#FF8A9D',linewidth=0.07,alpha=0.30,lineend='round')
logo$layers <- c(logo$layers[1],list(light_glow,light_core),logo$layers[-1])
hexSticker::save_sticker('man/figures/logo.png',logo,dpi=600)
