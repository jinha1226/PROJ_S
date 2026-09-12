extends RefCounted

var rows:Array = []
var sort_keys:int=2

func clear()->void:rows.clear()
func empty()->bool:return rows.is_empty()
func before(a:Array,b:Array)->bool:
	for i in range(sort_keys):
		if a[i]!=b[i]:return a[i]<b[i]
	return false
func push(row:Array)->void:
	rows.append(row)
	var index:=rows.size()-1
	while index>0:
		var parent:=(index-1)/2
		if not before(rows[index],rows[parent]):break
		var swap:Variant=rows[parent];rows[parent]=rows[index];rows[index]=swap
		index=parent
func pop()->Array:
	var result:Array=rows[0]
	var tail:Variant=rows.pop_back()
	if not rows.is_empty():
		rows[0]=tail
		var index:=0
		while index*2+1<rows.size():
			var child:=index*2+1
			if child+1<rows.size() and before(rows[child+1],rows[child]):child+=1
			if not before(rows[child],rows[index]):break
			var swap:Variant=rows[index];rows[index]=rows[child];rows[child]=swap
			index=child
	return result
